# Copyright © 2026 Anterior <tech@anterior.com>
# SPDX-License-Identifier: AGPL-3.0-only
"""
This walks every file to delete them if they haven't been selected to be
saved by the access logs.  The access logs are pruned with lifecycle
rules, thereby we only have pointers to the last n days of accessed files
in the cache.  I also considered using tags or mtime or object protection
to save objects and maybe use lifecycle to delete the other ones but each
has its own issue.

mtime: Can't update the time or version of an object without doing a
    literal PUT operation

tags: Can only do lifecycle on tags existing or their values.  So we'd
    have to apply the "delete" tag or something to every object and then
    delete it from the ones we want to save and then there's a race
    condition with the lifecycle rule.

object protection: We have to specify for how long to keep it protected.
    Now we have the logs which specify which files to save in the last
    month and then another parameter of how long to keep them? Do we
    check how long it's been in the logs and then compute how much longer
    to save or ??. Complicated and annoying.
"""

import asyncio
from collections.abc import Awaitable, Callable
from datetime import datetime, timezone
from functools import partial
import logging
import os
from typing import Any, TypedDict

import aioboto3
from aiobotocore.response import StreamingBody
import types_aiobotocore_s3
from types_aiobotocore_s3.service_resource import ObjectSummary

logger = logging.getLogger(__name__)

KEEP_SMALLER_THAN = (2**10) ** 3
N_WORKERS = 50


async def create_worker[P, R](
    fn: Callable[[P], Awaitable[R]],
    q: asyncio.Queue[P],
    update_fn: Callable[[R], None]
) -> None:
    while True:
        try:
            input = await q.get()
        except asyncio.QueueShutDown:
            return
        update_fn(await fn(input))
        q.task_done()


class HasStreamingBody(TypedDict):
    Body: StreamingBody


async def read_obj_lines(obj: HasStreamingBody) -> list[str]:
    async with obj["Body"] as body:
        return (await body.read()).decode("utf-8").strip().split("\n")


async def parse_logs_obj(obj: ObjectSummary, role: str) -> set[str]:
    lines = await read_obj_lines(await obj.get())
    lines_split = (x.split(" ") for x in lines)
    o: set[str] = set()
    for x in lines_split:
        logger.debug(f"{role=} logs_role={x[5]} ignored={role in x[5]}")
        # ignore the cleaner script iam role
        if role not in x[5]:
            o.add(x[8])
    return o


async def del_if_not_whitelisted(
    obj: ObjectSummary,
    save: set[str],
) -> None:
    if obj.key in save | {"nix-cache-info"}:
        logger.debug(f"saving {obj.key} from deletion because whitelist")
        return
    if (size := await obj.size) < KEEP_SMALLER_THAN:
        logger.debug(
            f"saving {obj.key} from deletion because {
                size=} < {KEEP_SMALLER_THAN}"
        )
        return
    # Takes a while to propagate the access logs, so spare everything written
    # in the last day
    if (
        datetime.now(timezone.utc) - (last_modified := await obj.last_modified)
    ).days < 1:
        logger.debug(
            f"saving {obj.key} from deletion because {
                last_modified=} within the last day"
        )
        return

    logger.debug(f"deleting {obj.key}")
    _ = await obj.delete()


# i would instead pass the getter fn by partially applying the bucket name to
# get_object, but the typing is atrocious
async def get_and_parse_narinfo(
    narinfo_name: str,
    s3c: types_aiobotocore_s3.Client,
    bucket: str,
) -> str | None:
    try:
        narinfo = await s3c.get_object(Bucket=bucket, Key=narinfo_name)
    except s3c.exceptions.NoSuchKey:
        return None
    lines = await read_obj_lines(narinfo)
    return lines[1].split("URL: ")[1]


async def main(
    *,
    cache_logs_name: str,
    cache_name: str,
    logs_key_prefix: str,
    log_level: str,
    role: str,
) -> None:
    logger.setLevel(log_level)

    session = aioboto3.Session()

    s3r: types_aiobotocore_s3.ServiceResource
    s3c: types_aiobotocore_s3.Client
    async with session.resource("s3") as s3r, session.client("s3") as s3c:
        bucket = await s3r.Bucket(cache_logs_name)

        # 1a. get logs phase including binaries to whitelist, and narinfo to
        # whitelist and follow
        logs_out: set[str] = set()
        parse_q: asyncio.Queue[ObjectSummary] = asyncio.Queue(
            maxsize=N_WORKERS)

        async def enqueue_parse() -> None:
            async for parse_job in bucket.objects.filter(
                Prefix=logs_key_prefix,
            ):
                await parse_q.put(parse_job)
            parse_q.shutdown()

        _ = await asyncio.gather(
            enqueue_parse(),
            *(create_worker(
                fn=partial(parse_logs_obj, role=role),
                q=parse_q,
                update_fn=logs_out.update,
            ) for _ in range(N_WORKERS)),
        )
        # This debug log and the similar ones below are fairly unconventional.
        # They are closer to TRACE or print debugging, but still useful for
        # now.  Can't all be one log because it will overrun the allowed log
        # message size.
        logger.debug("logs_out=")
        for log in logs_out:
            logger.debug(log)

        # 1b. follow narinfo files and add to whitelist
        nar_out: set[str] = set()
        nar_q: asyncio.Queue[str] = asyncio.Queue(maxsize=N_WORKERS)

        async def enqueue_nar() -> None:
            for narinfo in filter(lambda e: ".narinfo" in e, logs_out):
                await nar_q.put(narinfo)
            nar_q.shutdown()

        def update_fn_nar(parsed: str | None) -> None:
            if parsed is not None:
                nar_out.add(parsed)

        _ = await asyncio.gather(
            enqueue_nar(),
            *(create_worker(
                fn=partial(get_and_parse_narinfo, s3c=s3c, bucket=cache_name),
                q=nar_q,
                update_fn=update_fn_nar,
            )
                for _ in range(N_WORKERS)
            ),
        )
        logger.debug("nar_out=")
        for nar in nar_out:
            logger.debug(nar)

        save = nar_out | logs_out
        logger.debug("save=")
        for s in save:
            logger.debug(s)

        # 2. deletion phase, saving whitelisted files
        cache = await s3r.Bucket(cache_name)
        delete_q: asyncio.Queue[ObjectSummary] = asyncio.Queue(
            maxsize=N_WORKERS)

        async def enqueue_delete() -> None:
            async for x in cache.objects.filter(Prefix=""):
                await delete_q.put(x)
            delete_q.shutdown()

        _ = await asyncio.gather(
            enqueue_delete(),
            *(create_worker(
                fn=partial(del_if_not_whitelisted, save=save),
                q=delete_q,
                update_fn=lambda _: None,  # nop
            )
                for _ in range(N_WORKERS)),
        )


def aws_lambda(*args: str, **kwargs: dict[str, Any]) -> None:
    asyncio.run(
        main(
            cache_logs_name=os.environ["CACHE_LOGS_NAME"],
            cache_name=os.environ["CACHE_NAME"],
            log_level=os.environ["LOG_LEVEL"],
            logs_key_prefix=os.environ["LOGS_KEY_PREFIX"],
            role=os.environ["ROLE"],
        )
    )

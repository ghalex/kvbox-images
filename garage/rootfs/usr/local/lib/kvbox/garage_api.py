# What the kvbox-garage-* scripts share (kvbox #182): calling Garage's admin API on this box through
# `garage json-api` (Garage 2.0+: over the local RPC, so no admin token exists), and the contract of a
# kvbox-agent script: one JSON value on stdin, one on stdout, and on failure a non-zero exit whose
# last stderr line is the message the user reads.
import json
import subprocess
import sys

CONF = "/etc/garage.toml"


class ApiError(Exception):
    pass


def api(operation, body=None, timeout=20):
    """One admin API call; its JSON answer, or None when the answer is empty."""
    cmd = ["garage", "-c", CONF, "json-api", operation]
    if body is not None:
        cmd.append(json.dumps(body))
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as err:
        raise ApiError(f"the storage server did not answer ({err.__class__.__name__})") from err
    if r.returncode != 0:
        lines = [line for line in r.stderr.strip().splitlines() if line.strip()]
        raise ApiError(lines[-1] if lines else f"{operation} failed")
    text = r.stdout.strip()
    return json.loads(text) if text else None


def bucket_named(name):
    """The bucket's info, or None when there is no bucket of that name."""
    try:
        return api("GetBucketInfo", {"globalAlias": name})
    except ApiError as err:
        if "not found" in str(err).lower() or "nosuchbucket" in str(err).lower():
            return None
        raise


def read_input():
    data = json.loads(sys.stdin.readline() or "null")
    if not isinstance(data, dict):
        fail("expected a JSON object on stdin")
    return data


def text(data, field):
    value = data.get(field)
    if not isinstance(value, str) or value == "":
        fail(f'"{field}" is missing')
    return value


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def run(main):
    try:
        print(json.dumps(main()))
    except ApiError as err:
        fail(str(err))

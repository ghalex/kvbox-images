# What the kvbox-garage-* scripts share (kvbox #182): calling Garage's admin API on this box through
# `garage json-api` (Garage 2.0+: over the local RPC, so no admin token exists), a bucket's S3
# settings the admin API does not have (CORS, lifecycle) through `s3()`, and the contract of a
# kvbox-agent script: one JSON value on stdin, one on stdout, and on failure a non-zero exit whose
# last stderr line is the message the user reads.
import base64
import datetime
import hashlib
import hmac
import http.client
import json
import os
import re
import subprocess
import sys
import urllib.parse

# KVBOX_GARAGE_CONF only for trying the scripts against a Garage outside a box.
CONF = os.environ.get("KVBOX_GARAGE_CONF", "/etc/garage.toml")


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


def bucket_name(info):
    """A bucket's kvbox name: its alias without a dot (kvbox's bucket names have none). Any other is a host name."""
    for alias in info.get("globalAliases") or []:
        if "." not in alias:
            return alias
    return None


def web_hosts(info):
    """The host names a public bucket answers at, without a signature (port 3902): its aliases with a dot."""
    return [a for a in info.get("globalAliases") or [] if "." in a]


def _setting(name):
    try:
        with open(CONF, encoding="utf-8") as f:
            m = re.search(rf'^{name} = "(.*)"$', f.read(), re.M)
    except OSError:
        return None
    return m.group(1) if m else None


def _hmac(key, msg):
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()


def s3(bucket_id, bucket, method, subresource, body=b"", timeout=20):
    """
    One S3 call on a bucket's settings (`cors`, `lifecycle`): (status, body). The admin API has no such
    settings, and S3 takes them only from a key with the owner permission, which no key of the user's
    has. So a key is made for this one call and removed after it; its secret never leaves this process.
    """
    port = int((_setting("api_bind_addr") or ":3900").rsplit(":", 1)[1])
    region = _setting("s3_region") or "us-east-1"
    key = api("CreateKey", {"name": "kvbox-script"})
    try:
        api("AllowBucketKey", {"bucketId": bucket_id, "accessKeyId": key["accessKeyId"], "permissions": {"read": False, "write": False, "owner": True}})
        now = datetime.datetime.now(datetime.timezone.utc)
        stamp, day = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
        path = "/" + urllib.parse.quote(bucket, safe="")
        headers = {"host": f"127.0.0.1:{port}", "x-amz-content-sha256": hashlib.sha256(body).hexdigest(), "x-amz-date": stamp}
        if body:
            headers["content-md5"] = base64.b64encode(hashlib.md5(body).digest()).decode()
            headers["content-type"] = "application/xml"
        names = sorted(headers)
        canonical = "\n".join([method, path, f"{subresource}=", *(f"{n}:{headers[n]}" for n in names), "", ";".join(names), headers["x-amz-content-sha256"]])
        scope = f"{day}/{region}/s3/aws4_request"
        to_sign = "\n".join(["AWS4-HMAC-SHA256", stamp, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        signing = _hmac(_hmac(_hmac(_hmac(("AWS4" + key["secretAccessKey"]).encode(), day), region), "s3"), "aws4_request")
        signature = hmac.new(signing, to_sign.encode(), hashlib.sha256).hexdigest()
        headers["authorization"] = f"AWS4-HMAC-SHA256 Credential={key['accessKeyId']}/{scope}, SignedHeaders={';'.join(names)}, Signature={signature}"
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
        try:
            conn.request(method, f"{path}?{subresource}=", body=body or None, headers=headers)
            r = conn.getresponse()
            return r.status, r.read()
        except OSError as err:
            raise ApiError(f"the storage server did not answer ({err.__class__.__name__})") from err
        finally:
            conn.close()
    finally:
        api("DeleteKey", {"id": key["accessKeyId"]})


def s3_ok(result, what):
    """The body of a successful `s3()` answer; a failure as an ApiError naming what was being done."""
    status, body = result
    if status >= 300:
        m = re.search(rb"<Message>(.*?)</Message>", body or b"", re.S)
        raise ApiError(f"{what}: {m.group(1).decode() if m else f'HTTP {status}'}")
    return body


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

"""Checks the object store the way the services will use it: put, presigned GET, range read, presigned PUT."""

import urllib.request

import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:9000",
    aws_access_key_id="likho-dev",
    aws_secret_access_key="likho-dev-secret",
    region_name="us-east-1",
    config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
)

print("buckets:", sorted(b["Name"] for b in s3.list_buckets()["Buckets"]))

body = bytes(range(256)) * 400  # 102,400 bytes
s3.put_object(Bucket="likho-audio", Key="smoke/test.bin", Body=body, ContentType="audio/mpeg")
head = s3.head_object(Bucket="likho-audio", Key="smoke/test.bin")
print("put + head:", head["ContentLength"], head["ContentType"])

url = s3.generate_presigned_url("get_object", Params={"Bucket": "likho-audio", "Key": "smoke/test.bin"}, ExpiresIn=120)
with urllib.request.urlopen(url) as r:
    print("presigned GET:", r.status, len(r.read()) == len(body))

req = urllib.request.Request(url, headers={"Range": "bytes=1000-1999"})
with urllib.request.urlopen(req) as r:
    part = r.read()
    print("range read:", r.status, r.headers.get("Content-Range"), part == body[1000:2000])

put_url = s3.generate_presigned_url("put_object", Params={"Bucket": "likho-audio", "Key": "smoke/upload.bin"}, ExpiresIn=120)
req = urllib.request.Request(put_url, data=b"uploaded through a presigned link", method="PUT")
with urllib.request.urlopen(req) as r:
    print("presigned PUT:", r.status)
print("read back:", s3.get_object(Bucket="likho-audio", Key="smoke/upload.bin")["Body"].read().decode())

try:
    anon = urllib.request.urlopen("http://localhost:9000/likho-audio/smoke/test.bin")
    print("anonymous read: ALLOWED (unexpected)", anon.status)
except Exception as exc:  # noqa: BLE001
    print("anonymous read refused:", getattr(exc, "code", exc))

for key in ("smoke/test.bin", "smoke/upload.bin"):
    s3.delete_object(Bucket="likho-audio", Key=key)
print("cleaned up:", s3.list_objects_v2(Bucket="likho-audio").get("KeyCount"))

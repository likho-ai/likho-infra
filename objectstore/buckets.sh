#!/bin/sh
# Creates the buckets. Safe to run again.
set -eu
for bucket in likho-audio likho-normalized likho-peaks likho-models; do
  echo "s3.bucket.create -name $bucket" | weed shell -master=objectstore:9333 >/dev/null 2>&1 || true
done
echo "s3.bucket.list" | weed shell -master=objectstore:9333

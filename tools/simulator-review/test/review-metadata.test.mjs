import assert from "node:assert/strict";
import test from "node:test";

import { createReviewMetadata } from "../src/review-metadata.mjs";

test("requires an explicit simulator UDID", () => {
  assert.throws(() => createReviewMetadata({}), /simulator UDID/i);
});

test("normalizes simulator review metadata", () => {
  assert.deepEqual(createReviewMetadata({
    udid: "  1234-ABCD  ",
    device: "  iPhone 17 Pro  ",
    os: "  iOS 26.1  ",
    revision: "  abc1234  ",
    capturedAt: "2026-11-19T09:30:00.000Z",
  }), {
    udid: "1234-ABCD",
    device: "iPhone 17 Pro",
    os: "iOS 26.1",
    revision: "abc1234",
    capturedAt: "2026-11-19T09:30:00.000Z",
  });
});

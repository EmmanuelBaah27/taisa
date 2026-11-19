export function createReviewMetadata(input) {
  const udid = input.udid?.trim();
  if (!udid) throw new Error("An explicit simulator UDID is required");

  return {
    udid,
    device: input.device?.trim() || "Unknown simulator",
    os: input.os?.trim() || "Unknown OS",
    revision: input.revision?.trim() || "Unknown revision",
    capturedAt: input.capturedAt || new Date().toISOString(),
  };
}

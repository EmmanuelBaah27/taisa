import React from "react";

export function ReviewOverlay({ metadata }) {
  if (!metadata) return null;
  return (
    <aside
      data-taisa-simulator={metadata.udid}
      data-taisa-revision={metadata.revision}
      style={{
        position: "fixed",
        left: 12,
        bottom: 12,
        zIndex: 2147483000,
        maxWidth: 320,
        padding: "8px 10px",
        borderRadius: 8,
        background: "rgba(18, 18, 20, 0.86)",
        color: "white",
        font: "12px/1.35 -apple-system, BlinkMacSystemFont, sans-serif",
        pointerEvents: "none",
      }}
    >
      <div>{metadata.device} · {metadata.os} · {metadata.revision}</div>
      <div style={{ opacity: 0.72 }}>Pause the frame in Agentation before commenting.</div>
    </aside>
  );
}

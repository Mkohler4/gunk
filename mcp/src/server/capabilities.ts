import type { ServerCapabilities } from "@modelcontextprotocol/sdk/types.js";

export const SERVER_CAPABILITIES = {
  tools: {
    listChanged: false,
  },
} satisfies ServerCapabilities;

// License detection. Ported from app/Sources/GunkApp/Extract/LicenseDetector.swift.

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

export interface DetectedLicense {
  detected: string;
  warning: string | null;
}

export class LicenseDetector {
  detect(sourceRoot: string): DetectedLicense {
    const licenseFile = this.topLevelLicenseFile(sourceRoot);
    if (!licenseFile) {
      return { detected: "unknown", warning: null };
    }
    let contents: string;
    try {
      contents = readFileSync(licenseFile, "utf-8");
    } catch {
      return { detected: "unknown", warning: null };
    }
    const detected = this.spdxIdentifier(contents);
    const warning = this.isRestrictive(detected)
      ? `Restrictive source license detected: ${detected}. Reuse may require extra review.`
      : null;
    return { detected, warning };
  }

  private topLevelLicenseFile(sourceRoot: string): string | null {
    let entries: string[];
    try {
      entries = readdirSync(sourceRoot, { withFileTypes: true })
        .filter((e) => e.isFile() && !e.name.startsWith("."))
        .map((e) => e.name);
    } catch {
      return null;
    }
    const match = entries.find((name) => {
      const lower = name.toLowerCase();
      return lower === "license" || lower.startsWith("license.") || lower === "copying" || lower.startsWith("copying.");
    });
    return match ? join(sourceRoot, match) : null;
  }

  private spdxIdentifier(contents: string): string {
    const upper = contents.toUpperCase();
    if (upper.includes("GNU AFFERO GENERAL PUBLIC LICENSE")) return this.versionedGPL("AGPL", upper);
    if (upper.includes("GNU LESSER GENERAL PUBLIC LICENSE")) return this.versionedGPL("LGPL", upper);
    if (upper.includes("GNU GENERAL PUBLIC LICENSE")) return this.versionedGPL("GPL", upper);
    if (upper.includes("APACHE LICENSE")) return "Apache-2.0";
    if (upper.includes("MIT LICENSE") || upper.includes("PERMISSION IS HEREBY GRANTED")) return "MIT";
    if (upper.includes("BSD 3-CLAUSE")) return "BSD-3-Clause";
    if (upper.includes("BSD 2-CLAUSE")) return "BSD-2-Clause";
    if (upper.includes("ISC LICENSE")) return "ISC";
    if (upper.includes("MOZILLA PUBLIC LICENSE")) return "MPL-2.0";
    return "unknown";
  }

  private versionedGPL(prefix: string, contents: string): string {
    if (contents.includes("VERSION 3")) return `${prefix}-3.0-or-later`;
    if (contents.includes("VERSION 2")) return `${prefix}-2.0-or-later`;
    return prefix;
  }

  private isRestrictive(identifier: string): boolean {
    return identifier.startsWith("GPL") || identifier.startsWith("AGPL") || identifier.startsWith("LGPL");
  }
}

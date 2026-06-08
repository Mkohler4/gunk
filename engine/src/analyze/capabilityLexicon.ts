export interface CapabilityHint {
  library: string;
  labels: string[];
}

const DEFAULT_ENTRIES: Record<string, string[]> = {
  "passport-google-oauth20": ["auth", "google", "oauth"],
  "google-auth-library": ["auth", "google"],
  "next-auth": ["auth"],
  "@auth/core": ["auth"],
  "@clerk/nextjs": ["auth", "clerk"],
  auth0: ["auth", "auth0"],
  stripe: ["payments", "billing"],
  "@stripe/stripe-js": ["payments", "billing"],
  "flutter_stripe": ["payments", "billing"],
  "stripe_android": ["payments", "billing"],
  "stripe-android": ["payments", "billing"],
  "com.stripe:stripe-android": ["payments", "billing"],
  "billing-ktx": ["payments", "billing"],
  "com.android.billingclient:billing-ktx": ["payments", "billing"],
  "paypal-rest-sdk": ["payments", "paypal"],
  twilio: ["messaging", "sms"],
  "@sendgrid/mail": ["email", "sendgrid"],
  nodemailer: ["email"],
  openai: ["ai", "openai"],
  langchain: ["ai", "llm"],
  firebase: ["firebase"],
  "firebase_auth": ["auth", "firebase"],
  "firebase-auth": ["auth", "firebase"],
  "com.google.firebase:firebase-auth": ["auth", "firebase"],
  "flutter_secure_storage": ["storage", "secure-storage"],
  dio: ["network"],
  http: ["network"],
  retrofit: ["network"],
  "com.squareup.retrofit2:retrofit": ["network"],
  "play-services-location": ["location"],
  "com.google.android.gms:play-services-location": ["location"],
  "@aws-sdk/client-s3": ["storage", "s3", "aws"],
  "aws-sdk": ["aws"],
  pg: ["database", "postgres"],
  prisma: ["database", "orm"],
};

function normalize(value: string): string {
  return value.toLowerCase().trim();
}

export class CapabilityLexicon {
  private readonly entries: Map<string, string[]>;

  constructor(entries: Record<string, string[]> = DEFAULT_ENTRIES) {
    this.entries = new Map();
    for (const [key, labels] of Object.entries(entries)) {
      this.entries.set(normalize(key), labels);
    }
  }

  static readonly default = new CapabilityLexicon();

  hint(library: string): CapabilityHint | null {
    const labels = this.entries.get(normalize(library));
    if (!labels) {
      return null;
    }

    return { library, labels: [...labels] };
  }
}

/** Stable key used to dedupe capability hints (Swift `Set<CapabilityHint>` parity). */
export function capabilityHintKey(hint: CapabilityHint): string {
  return `${hint.library}\u0000${[...hint.labels].sort().join("/")}`;
}

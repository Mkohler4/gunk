import nodemailer from "nodemailer";
import { mailConfig } from "../config/mail";
import type { InviteResult } from "../types/invite";

export async function sendInvite(email: string): Promise<InviteResult> {
  const transport = nodemailer.createTransport(mailConfig.smtpUrl);
  await transport.sendMail({ to: email, subject: "Invite", text: "Join us" });
  return { email, sent: true };
}

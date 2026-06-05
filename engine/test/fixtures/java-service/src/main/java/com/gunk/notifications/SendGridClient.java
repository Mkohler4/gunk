package com.gunk.notifications;
class SendGridClient { EmailResult send(EmailRequest request) { return new EmailResult(request.to(), "queued"); } }

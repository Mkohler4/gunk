package com.gunk.notifications;
class EmailService { private final SendGridClient client; EmailService(SendGridClient client) { this.client = client; } EmailResult sendInvite(EmailRequest request) { return client.send(request); } }

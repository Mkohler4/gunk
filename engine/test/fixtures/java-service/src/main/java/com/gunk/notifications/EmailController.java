package com.gunk.notifications;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;
@RestController
class EmailController { private final EmailService service = new EmailService(new SendGridClient()); @PostMapping("/emails/invite") EmailResult sendInvite(EmailRequest request) { return service.sendInvite(request); } }

# cURL wraps

For using you need installed `libcurl`.

## sendmail

Simple example:

```d
import curlwrap.sendmail;

auto sets = SMTPSettings("smtp.example.com", 465, "user@example.com", "userpassword");
auto ms = new MailSender(sets);

auto from = Mail.User("user@example.com", "noreply");
auto to = Mail.User("john@example.com", "Mr. John");

ms.send(Mail(from, [to], "Subject", "Mail body", Clock.currTime));
```

See [`sendmail.d`](source/curlwrap/sendmail.d) for details
and [`example`](example/sendmail_example.d) for working example.
#!/usr/bin/env dub
/+ dub.sdl:
    name "sendmailex"
    dependency "curlwrap" path=".."
+/

import std.stdio;
import std.array : appender;
import std.format : formattedWrite;
import std.range : put;
import std.getopt;
import std.datetime;

import curlwrap.sendmail;

void main(string[] args)
{
    SMTPSettings sets;
    sets.port = 465;

    Mail.User to;
    string subj = "Program mail";
    string text;
    bool starttls;

    getopt(args,
        "s|server", &sets.server,
        "port",     &sets.port,
        "u|user",   &sets.username,
        "p|pass",   &sets.password,
        "r|recipient",     &to.addr,
        "subject",  &subj,
        "t|text",   &text,
        "starttls", &starttls
    );

    stderr.writeln(sets);

    if (starttls) sets.security = sets.Security.starttls;

    auto ms = new MailSender(sets);
    //ms.verbose = true;

    auto from = Mail.User(sets.username, "noreply");
    ms.send(Mail(from, [to], subj, text, Clock.currTime));
}
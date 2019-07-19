///
module curlwrap.sendmail;

import std.range : put;
import std.exception : enforce;
import std.format : format, formattedWrite;
import std.array : appender, replace;
import std.datetime : SysTime, DateTime;
import std.string : fromStringz, toStringz;
import std.conv : to;

import etc.c.curl;

///
struct SMTPSettings
{
    ///
    string server;
    ///
    ushort port;

    /// need for auth on smtp server
    string username;
    /// ditto
    string password;

    ///
    enum Security
    {
        none, ///
        starttls, ///
        ssl_tls ///
    }
    /// if used `ssl_tls` algorithm try connect by `smtps` protocol instead `smtp`
    Security security = Security.ssl_tls;

    ///
    bool verifyPeer = false;
    ///
    bool verifyHost = false;

    ///
    enum Auth
    {
        none, ///
        usernameAndPassword ///
    }
    ///
    Auth auth = Auth.usernameAndPassword;
}

///
struct Mail
{
    ///
    struct User
    {
        /// e-mail address
        string addr;
        ///
        string name;
    }
    /// for some services 'from' e-mail in header must be equal user login
    User from;
    ///
    User[] recipients;
    ///
    string subject;
    ///
    string body;
    ///
    SysTime date;
    ///
    bool html;
}

///
interface MailBuilder
{
    ///
    string build(Mail mail);
}

///
class BasicMailBuilder : MailBuilder
{
    ///
    string build(Mail mail)
    {
        auto buf = appender!string;

        enum nl = "\r\n";

        if (mail.from.addr.length)
            formattedWrite(buf, "From: %s <%s>%s", mail.from.name,
                            mail.from.addr, nl);

        if (mail.recipients.length)
        {
            formattedWrite(buf, "To: ");
            foreach (i, r; mail.recipients)
            {
                formattedWrite(buf, "%s <%s>", r.name, r.addr);
                if (i != mail.recipients.length-1) put(buf, ", ");
            }
            put(buf, nl);
        }

        if (mail.subject.length)
            formattedWrite(buf, "Subject: %s%s", mail.subject, nl);

        auto c = mail.date;
        formattedWrite(buf, "Date: %s, %d %s %d %02d:%02d:%02d%s",
                    c.dayOfWeek(), c.day, (cast(DateTime)c).month,
                    c.year, c.hour, c.minute, c.second, nl);

        if (mail.html)
            formattedWrite(buf, "Content-Type: text/html; charset=\"UTF-8\"%s", nl);
        
        put(buf, nl);

        put(buf, mail.body.replace("\n", "\r\n"));

        return buf.data;
    }
}

unittest
{
    auto bmb = new BasicMailBuilder;
    auto ct = SysTime(DateTime(2019, 7, 19, 13, 45, 15));

    {
        auto m = Mail(Mail.User("user@example.com", "Sender"),
                        [Mail.User("r1@e.com", "R1")],
                        "Some subj", "text\nof\nemail", ct);
        assert (bmb.build(m) == "From: Sender <user@example.com>\r\n" ~
            "To: R1 <r1@e.com>\r\nSubject: Some subj\r\n" ~
            "Date: fri, 19 jul 2019 13:45:15\r\n" ~
            "\r\ntext\r\nof\r\nemail"
        );
    }

    {
        auto m = Mail(Mail.User("user@example.com", "Sender"),
                        [Mail.User("r1@e.com", "R1"),
                         Mail.User("r2@x.com", "R2")],
                        "Some subj", "text\nof\nemail", ct);
        assert (bmb.build(m) == "From: Sender <user@example.com>\r\n" ~
            "To: R1 <r1@e.com>, R2 <r2@x.com>\r\n" ~
            "Subject: Some subj\r\nDate: fri, 19 jul 2019 13:45:15\r\n" ~
            "\r\ntext\r\nof\r\nemail"
        );
    }

    {
        auto m = Mail(Mail.User("user@example.com", "Sender"), [],
                        "Some subj", "text\nof\nemail", ct);
        assert (bmb.build(m) == "From: Sender <user@example.com>\r\n" ~
            "Subject: Some subj\r\nDate: fri, 19 jul 2019 13:45:15\r\n" ~
            "\r\ntext\r\nof\r\nemail"
        );
    }

    {
        auto m = Mail(Mail.User("", "Sender"), [],
                        "Some subj", "text\nof\nemail", ct);
        assert (bmb.build(m) == "Subject: Some subj\r\n" ~
            "Date: fri, 19 jul 2019 13:45:15\r\n" ~
            "\r\ntext\r\nof\r\nemail"
        );
    }

    {
        auto m = Mail(Mail.User("", "Sender"), [],
                        "", "text\nof\nemail", ct);
        assert (bmb.build(m) == "Date: fri, 19 jul 2019 13:45:15\r\n" ~
            "\r\ntext\r\nof\r\nemail"
        );
    }
}

///
class MailSender
{
protected:
    CURL* curl;
    bool selfCreatedCURL;

    MailBuilder mailBuilder;
    BasicMailBuilder basicMailBuilder;

public:

    ///
    SMTPSettings settings;

    /// 
    bool verbose;

    ///
    this(CURL* curl, SMTPSettings sets)
    {
        settings = sets;
        this.curl = curl;
        basicMailBuilder = new BasicMailBuilder();
        mailBuilder = basicMailBuilder;
    }

    ///
    this(SMTPSettings sets)
    {
        curl = enforce(curl_easy_init(), "fail to init curl");
        selfCreatedCURL = true;
        this(curl, sets);
    }

    void setMailBuilder(MailBuilder builder)
    {
        if (builder) mailBuilder = builder;
        else mailBuilder = basicMailBuilder;
    }

    void cleanup()
    {
        if (!selfCreatedCURL) return;
        curl_easy_cleanup(curl);
        curl = null;
    }

    ~this() { if (curl) cleanup(); }

    ///
    void send(Mail mail)
    {
        void ces(Arg)(int opt, Arg arg)
        {
            static if (is(Arg == string))
                checkCurlCall!curl_easy_setopt(curl, opt, arg.toStringz);
            else
                checkCurlCall!curl_easy_setopt(curl, opt, arg);
        }

        curl_easy_reset(curl);

        if (verbose) ces(CurlOption.verbose, 1L);

        auto secureProto = settings.security == settings.Security.ssl_tls;
        auto url = format("smtp%s://%s:%s", (secureProto ? "s" : ""),
                            settings.server, settings.port);

        ces(CurlOption.url, url);

        if (settings.security == settings.Security.ssl_tls)
            ces(CurlOption.use_ssl, CurlUseSSL.all);
        else if (settings.security == settings.Security.starttls)
            ces(CurlOption.use_ssl, CurlUseSSL.tryssl);

        ces(CurlOption.mail_from, settings.username);
        ces(10_217, settings.username); // mail_auth

        curl_slist* rcpt_list;
        foreach (r; mail.recipients)
            rcpt_list = curl_slist_append(rcpt_list, r.addr.toStringz);
        scope (exit) curl_slist_free_all(rcpt_list);
        ces(CurlOption.mail_rcpt, rcpt_list);

        if (!settings.verifyHost) ces(CurlOption.ssl_verifyhost, 0L);
        if (!settings.verifyPeer) ces(CurlOption.ssl_verifypeer, 0L);

        if (settings.auth == settings.Auth.usernameAndPassword)
        {
            ces(CurlOption.username, settings.username);
            ces(CurlOption.password, settings.password);
        }

        auto mailBody = mailBuilder.build(mail);
        ces(CurlOption.readfunction, &readCallback);
        ces(CurlOption.readdata, &mailBody);
        ces(CurlOption.upload, 1L);

        checkCurlCall!curl_easy_perform(curl);
    }
}

private
{
    void checkCurlCall(alias fn, Args...)(Args args)
    {
        auto r = fn(args);
        if (r)
        {
            auto s = curl_easy_strerror(r).fromStringz.idup;
            throw new Exception(s);
        }
    }

    extern (C)
    size_t readCallback(char *buffer, size_t size, size_t nitems, void *instream)
    {
        auto data = (cast(string*)instream);

        const dl = data.length;
        const ln = size * nitems;

        auto l = ln < dl ? ln : dl;

        if (l < 1) return 0;

        buffer[0..l] = (*data)[0..l];
        (*data) = (*data)[l..$];

        return l;
    }
}
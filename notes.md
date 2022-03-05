Barnyard directory structure.

The minimal barnyard directory structure is the following.

```
$ find my-barnyard
```

These two directories are required. They can be empty, but they are required.

In the `modules` directory you create modules directories. The diretory name is
the module name. Within the module you write a `bash` program named `apply`.

```console
$ mkdir modules/motd
```

```bash
# modules/motd/apply
cat <<EOF > /etc/motd
"Ever make mistakes in life? Let’s make them birds. Yeah, they’re birds now."
--Bob Ross
EOF
```

In the `machines` directory you create a directory using the fully-qualified
domain name for each machine that you want to manage with Barnyard.

Inside that directory you create a configuration file for the modules you want
to run. Configuration files are simple name/value pairs. [TK Config file
format.]

The configuration file is whatever your module needs it to be. There are a set
of special configuration properties for managing dependencies.

The configuration is module specific. There are some special variables used by
Barnyard, they are prefixed with an `@`.

Configuration files.

Module configuration files are name/value pairs. The value must fit on one line.
For multi line values using `base64` encoding (maybe we decode?)

```
@dependencies=users
%dependencies=users
&included=../../includes/postgresql
&included=includes/postgresql
~base64=IEVkZy4gQ29tZSBvbiwgc2lyOyBoZXJlJ3MgdGhlIHBsYWNlLiBTdGFuZCBzdGlsbC4gSG93IGZlYXJmdWwKICAgICBBbmQgZGl6enkgJ3RpcyB0byBjYXN0IG9uZSdzIGV5ZXMgc28gbG93IQogICAgIFRoZSBjcm93cyBhbmQgY2hvdWdocyB0aGF0IHdpbmcgdGhlIG1pZHdheSBhaXIgIAogICAgIFNob3cgc2NhcmNlIHNvIGdyb3NzIGFzIGJlZXRsZXMuIEhhbGZ3YXkgZG93bgogICAgIEhhbmdzIG9uZSB0aGF0IGdhdGhlcnMgc2FtcGlyZS0gZHJlYWRmdWwgdHJhZGUhCiAgICAgTWV0aGlua3MgaGUgc2VlbXMgbm8gYmlnZ2VyIHRoYW4gaGlzIGhlYWQuCiAgICAgVGhlIGZpc2hlcm1lbiB0aGF0IHdhbGsgdXBvbiB0aGUgYmVhY2gKICAgICBBcHBlYXIgbGlrZSBtaWNlOyBhbmQgeW9uZCB0YWxsIGFuY2hvcmluZyBiYXJrLAogICAgIERpbWluaXNoJ2QgdG8gaGVyIGNvY2s7IGhlciBjb2NrLCBhIGJ1b3kKICAgICBBbG1vc3QgdG9vIHNtYWxsIGZvciBzaWdodC4gVGhlIG11cm11cmluZyBzdXJnZQogICAgIFRoYXQgb24gdGgnIHVubnVtYidyZWQgaWRsZSBwZWJibGUgY2hhZmVzCiAgICAgQ2Fubm90IGJlIGhlYXJkIHNvIGhpZ2guIEknbGwgbG9vayBubyBtb3JlLAogICAgIExlc3QgbXkgYnJhaW4gdHVybiwgYW5kIHRoZSBkZWZpY2llbnQgc2lnaHQKICAgICBUb3BwbGUgZG93biBoZWFkbG9uZy4K
sudoers=fred wilma
```

TODO Implement oneshot, diff and explicit types of modules, specify in config.

TODO Inform a module of what modules have run. That way we can have a generic
restart module, one that even accepts a regex, and restart a service when
certain modules have run.

TODO Implement run on diff.

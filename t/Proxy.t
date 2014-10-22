#! /usr/bin/perl

use strict;
use warnings;
use Test::More;
use JSON;
use LWP::UserAgent;
use Browsermob::Proxy;
use Net::HTTP::Spore::Middleware::Mock;

my $server_port = 63638;
my $port = 9091;

SPECIFY_PORT: {
    my $proxy = Browsermob::Proxy->new(
        server_port => $server_port,
        port => $port,
        mock => generate_mock_server()
    );

    ok(defined $proxy->port, 'created a proxy with our own port');
    if ($proxy->has_mock) {
        cmp_ok($proxy->port, 'eq', $port, 'on the default port');
    }

    my $res = $proxy->has_mock ? $proxy->delete_proxy : { body => ""};
    ok($res->{body} eq '', 'proxy deletes itself');
    # ok($delete_count eq 1, 'proxy deletes self when taken out of scope');
}

NO_PORT: {
    my $proxy = Browsermob::Proxy->new(
        server_port => $port,
        mock => generate_mock_server()
    );

    isa_ok($proxy, 'Browsermob::Proxy');
    ok(defined $proxy->port, 'Our new proxy has its own port!');
}

HAR: {
  CREATE_UNNAMED: {
        my $har_server = generate_mock_server();

        $har_server->{'/proxy/' . $port . '/har'} = sub {
            my $req = shift;
            ok($req->method eq 'PUT', 'creating a har uses PUT');
            ok($req->body eq '{}', 'unnamed har body is empty');
            $req->new_response(200, ['Content-Type' => 'application/json'], "");
        };

        my $proxy = Browsermob::Proxy->new(
            server_port => $server_port,
            port => $port,
            mock => $har_server
        );

        my $res = $proxy->new_har;
    }

  CREATE_NAMED: {
        my $har_server = generate_mock_server();

        $har_server->{'/proxy/' . $port . '/har'} = sub {
            my $req = shift;
            ok($req->method eq 'PUT', 'creating a named har uses PUT');
            ok($req->body eq '{"initialPageRef":"Google"}', 'body of new har has name');
            $req->new_response(200, ['Content-Type' => 'application/json'], "");
        };

        my $proxy = Browsermob::Proxy->new(
            server_port => $server_port,
            port => $port,
            mock => $har_server
        );

        my $res = $proxy->new_har('Google');
        ok($res->body eq "", 'got the expected response back when creating a named har');
    }

  RETRIEVE: {
        my $har_server = generate_mock_server();
        $har_server->{'/proxy/' . $port . '/har'} = sub {
            my $req = shift;
            ok($req->method eq 'GET', 'retrieving a har via GET');
            $req->new_response(200, ['Content-Type' => 'application/json'], fake_har_fixture());
        };

        my $proxy = Browsermob::Proxy->new(
            server_port => $server_port,
            port => $port,
            mock => $har_server
        );

        my $har = $proxy->har;
        isa_ok($har, 'HASH', 'the retrieved har is a hash');
        ok(exists $har->{log}, 'with a log entry');
        ok(exists $har->{log}->{entries}->[0], 'that has an entries arrayref');
    }
}

CAPABILITIES: {
  MANUAL_HAR: {
        my $proxy = Browsermob::Proxy->new(
            server_port => $server_port,
            port => $port,
            mock => generate_mock_server()
        );

        my $caps = $proxy->selenium_proxy(1);
        isa_ok($caps, 'HASH', 'caps is a hashref');
        ok($caps->{proxyType} eq 'manual', 'and has a proxyType');
        ok($caps->{httpProxy} =~ /$port/i, 'and a httpUrl proxyType to the correct port');

        my $addr = $proxy->server_addr;
        cmp_ok($caps->{httpProxy}, '=~', qr/$addr/i, 'and the correct server addr');

        ok($caps->{sslProxy} =~ /$port/i, 'and a httpUrl proxyType to the correct port in SSL');

        $addr = $proxy->server_addr;
        cmp_ok($caps->{sslProxy}, '=~', qr/$addr/i, 'and the correct server addr in SSL');
    }

  AUTOMATIC_NEW_HAR: {
        my $new_har_was_called = 0;
        my $mock_server = generate_mock_server();
        $mock_server->{'/proxy/' . $port . '/har'} = sub {
            my $req = shift;
            $new_har_was_called++;
            $req->new_response(200, ['Content-Type' => 'application/json'], "");
        };

        my $caps = Browsermob::Proxy->new(
            server_port => $server_port,
            port => $port,
            mock => $mock_server
        )->selenium_proxy;

        ok($new_har_was_called, 'invoking selenium_proxy creates a new har by default');
    }
}

sub generate_mock_server {
    my $mock_port = shift || $port;

    return {
        '/proxy/' => sub {
            my $req = shift;
            if ($req->method eq 'POST') {
                use Data::Dumper; use DDP;
                my $res = {
                    port => $mock_port
                };
                return $req->new_response(200, ['Content-Type' => 'application/json'], to_json($res));
            }
        },

        '/proxy/' . $mock_port => sub {
            my ($req) = @_;

            my %params;
            eval {
                %params = @{ $req->get_from_env("spore.params") };
            };

            if ($req->method eq 'DELETE') {
                die unless $params{port};
                return $req->new_response(200, ['Content-Type' => 'application/json'], "");
            }
        }
    }
}

sub fake_har_fixture {
    return '{"log":{"creator":{"comment":"","version":"2.0","name":"BrowserMob Proxy"},"comment":"","version":"1.2","entries":[{"request":{"bodySize":0,"cookies":[],"headers":[],"httpVersion":"HTTP","headersSize":102,"comment":"","url":"http://www.google.com/","method":"GET","queryString":[]},"timings":{"dns":97,"send":0,"ssl":0,"receive":8,"comment":"","wait":117,"blocked":0,"connect":43},"pageref":"Page 1","response":{"bodySize":11467,"cookies":[{"domain":".google.com","comment":"","value":"ID=9b9fccc5e3179766:FF=0:TM=1397078322:LM=1397078322:S=zNU0CgkD_fCR3d_h","name":"PREF","path":"/","expires":"2016-04-08T21:18:42.000+0000"},{"domain":".google.com","comment":"","value":"67=Jt7rVJxnccsjaJQ2cTzu2gMrUQvY4ncdIKiO6bemm51SiBU2u3QVBtQGJA5PB5_dVXti1BAnbaVqQoJLzBsacjeLi8-YAhBGuwsj4K0gwA1aNsDOxvvR0nEwsCGrxWK_","name":"NID","path":"/","expires":"2014-10-09T21:18:42.000+0000"}],"headers":[],"status":200,"httpVersion":"HTTP","content":{"comment":"","mimeType":"text/html; charset=ISO-8859-1","size":11467},"statusText":"OK","headersSize":793,"comment":"","redirectURL":""},"time":265,"startedDateTime":"2014-04-09T21:18:44.512+0000","serverIPAddress":"74.125.225.50","comment":"","cache":{}}],"browser":{"comment":"","version":"7.30.0","name":"cURL"},"pages":[{"comment":"","title":"","pageTimings":{"comment":""},"id":"Page 1","startedDateTime":"2014-04-09T21:18:44.503+0000"}]}}'
}

done_testing;

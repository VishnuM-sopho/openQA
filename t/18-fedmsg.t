#! /usr/bin/perl

# Copyright (C) 2016 Red Hat
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

BEGIN {
    unshift @INC, 'lib';
    $ENV{OPENQA_TEST_IPC} = 1;
}

use Mojo::Base;
use Mojo::IOLoop;

use FindBin;
use lib "$FindBin::Bin/lib";
use OpenQA::Client;
use OpenQA::Scheduler;
use OpenQA::WebSockets;
use OpenQA::Test::Database;
use Net::DBus;
use Net::DBus::Test::MockObject;
use Test::MockModule;
use Test::More;
use Test::Mojo;
use Test::Warnings;
use Mojo::File qw(tempdir path);

my $args;

# this is a mock IPC::Run which just stores the args it's called with
# so we can check the plugin did the right thing
sub mock_ipc_run {
    my ($cmd, $stdin, $stdout, $stderr) = @_;
    $args = join(" ", @$cmd);
}

my $module = new Test::MockModule('IPC::Run');
$module->mock('run', \&mock_ipc_run);

my $schema = OpenQA::Test::Database->new->create();

# this test also serves to test plugin loading via config file
my @conf = ("[global]\n", "plugins=Fedmsg\n");
$ENV{OPENQA_CONFIG} = tempdir;
path($ENV{OPENQA_CONFIG})->make_path->child("openqa.ini")->spurt(@conf);

my $t = Test::Mojo->new('OpenQA::WebAPI');

# XXX: Test::Mojo loses its app when setting a new ua
# https://github.com/kraih/mojo/issues/598
my $app = $t->app;
$t->ua(
    OpenQA::Client->new(apikey => 'PERCIVALKEY02', apisecret => 'PERCIVALSECRET02')->ioloop(Mojo::IOLoop->singleton));
$t->app($app);

# create Test DBus bus and service for fake WebSockets
my $ws = OpenQA::WebSockets->new();
my $sh = OpenQA::Scheduler->new();

my $settings = {
    DISTRI      => 'Unicorn',
    FLAVOR      => 'pink',
    VERSION     => '42',
    BUILD       => '666',
    TEST        => 'rainbow',
    ISO         => 'whatever.iso',
    DESKTOP     => 'DESKTOP',
    KVM         => 'KVM',
    ISO_MAXSIZE => 1,
    MACHINE     => "RainbowPC",
    ARCH        => 'x86_64'
};

my $commonexpr = '/usr/sbin/daemonize /usr/bin/fedmsg-logger --cert-prefix=openqa --modname=openqa';
# create a job via API
my $post = $t->post_ok("/api/v1/jobs" => form => $settings)->status_is(200);
my $job = $post->tx->res->json->{id};
is(
    $args,
    $commonexpr
      . ' --topic=job.create --json-input --message='
      . '{"ARCH":"x86_64","BUILD":"666","DESKTOP":"DESKTOP","DISTRI":"Unicorn","FLAVOR":"pink","ISO":"whatever.iso",'
      . '"ISO_MAXSIZE":"1","KVM":"KVM","MACHINE":"RainbowPC","TEST":"rainbow","VERSION":"42","id":'
      . $job
      . ',"remaining":1}',
    "job create triggers fedmsg"
);
# reset $args
$args = '';

# FIXME: restarting job via API emits an event in real use, but not if we do it here

# set the job as done via API
$post = $t->post_ok("/api/v1/jobs/" . $job . "/set_done")->status_is(200);
# check plugin called fedmsg-logger correctly
is(
    $args,
    $commonexpr
      . ' --topic=job.done --json-input --message='
      . '{"ARCH":"x86_64","BUILD":"666","FLAVOR":"pink","ISO":"whatever.iso","MACHINE":"RainbowPC",'
      . '"TEST":"rainbow","id":'
      . $job
      . ',"newbuild":null,"remaining":0,"result":"failed"}',
    "job done triggers fedmsg"
);
# reset $args
$args = '';

# we don't test update_results as comment indicates it's obsolete

# duplicate the job via API
$post = $t->post_ok("/api/v1/jobs/" . $job . "/duplicate")->status_is(200);
my $newjob = $post->tx->res->json->{id};
# check plugin called fedmsg-logger correctly
is(
    $args,
    $commonexpr
      . ' --topic=job.duplicate --json-input --message='
      . '{"ARCH":"x86_64","BUILD":"666","FLAVOR":"pink","ISO":"whatever.iso","MACHINE":"RainbowPC",'
      . '"TEST":"rainbow","auto":0,"id":'
      . $job
      . ',"remaining":1,"result":'
      . $newjob . '}',
    "job duplicate triggers fedmsg"
);
# reset $args
$args = '';

# cancel the new job via API
$post = $t->post_ok("/api/v1/jobs/" . $newjob . "/cancel")->status_is(200);
# check plugin called fedmsg-logger correctly
is(
    $args,
    $commonexpr
      . ' --topic=job.cancel --json-input --message='
      . '{"ARCH":"x86_64","BUILD":"666","FLAVOR":"pink","ISO":"whatever.iso","MACHINE":"RainbowPC",'
      . '"TEST":"rainbow","id":'
      . $newjob
      . ',"remaining":0}',
    "job cancel triggers fedmsg"
);
# reset $args
$args = '';

# FIXME: deleting job via DELETE call to api/v1/jobs/$newjob fails with 500?

# add a job comment via API
$post = $t->post_ok("/api/v1/jobs/$job/comments" => form => {text => "test comment"})->status_is(200);
# stash the comment ID
my $comment = $post->tx->res->json->{id};
# check plugin called fedmsg-logger correctly
my $dateexpr = '\d{4}-\d{1,2}-\d{1,2}T\d{2}:\d{2}:\d{2}Z';
like(
    $args,
qr/$commonexpr --topic=comment.create --json-input --message=\{"created":"$dateexpr","group_id":null,"id":$comment,"job_id":$job,"text":"test comment","updated":"$dateexpr","user":"perci"\}/,
    'comment post triggers fedmsg'
);
# reset $args
$args = '';

# update job comment via API
my $put = $t->put_ok("/api/v1/jobs/$job/comments/$comment" => form => {text => "updated comment"})->status_is(200);
# check plugin called fedmsg-logger correctly
like(
    $args,
qr/$commonexpr --topic=comment.update --json-input --message=\{"created":"$dateexpr","group_id":null,"id":$comment,"job_id":$job,"text":"updated comment","updated":"$dateexpr","user":"perci"\}/,
    'comment update triggers fedmsg'
);
# reset $args
$args = '';

# become admin (so we can delete the comment)
$t->ua(OpenQA::Client->new(apikey => 'ARTHURKEY01', apisecret => 'EXCALIBUR')->ioloop(Mojo::IOLoop->singleton));
$t->app($app);
# delete comment via API
my $delete = $t->delete_ok("/api/v1/jobs/$job/comments/$comment")->status_is(200);
like(
    $args,
qr/$commonexpr --topic=comment.delete --json-input --message=\{"created":"$dateexpr","group_id":null,"id":$comment,"job_id":$job,"text":"updated comment","updated":"$dateexpr","user":"perci"\}/,
    'comment delete triggers fedmsg'
);
# reset $args
$args = '';

done_testing();

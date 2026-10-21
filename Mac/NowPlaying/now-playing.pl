#!/usr/bin/perl
# Loads DashUp's MediaRemote bridge into Apple's perl, which macOS still lets read Now Playing.
# Usage: DASHUP_MR_COMMAND=stream /usr/bin/perl now-playing.pl /path/to/libDashUpMediaRemote.dylib
use strict;
use warnings;
use DynaLoader;
my $path = shift or die "usage: now-playing.pl <dylib>\n";
my $lib = DynaLoader::dl_load_file($path, 0) or die "load failed: " . DynaLoader::dl_error() . "\n";
my $sym = DynaLoader::dl_find_symbol($lib, "dashup_main") or die "symbol missing\n";
DynaLoader::dl_install_xsub("main::dashup_main", $sym);
dashup_main();

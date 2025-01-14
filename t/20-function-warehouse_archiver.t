use strict;
use warnings;
use Test::More tests => 4;
use Test::Exception;
use Log::Log4perl qw(:levels);

use t::util;

my $util = t::util->new();
Log::Log4perl->easy_init({layout => '%d %-5p %c - %m%n',
                          level  => $DEBUG,
                          file   => join(q[/], $util->temp_directory(), 'logfile'),
                          utf8   => 1});

my $runfolder_path = $util->analysis_runfolder_path();
my $pqq_suffix = q[_post_qc_complete];
my @wh_methods = qw/update_ml_warehouse/;
@wh_methods = map {$_, $_ . $pqq_suffix} @wh_methods;

use_ok('npg_pipeline::function::warehouse_archiver');

my $default = {
  default => {
    minimum_cpu => 0,
    memory => 2,
    queue => 'lowload'
  }
};

subtest 'warehouse updates' => sub {
  plan tests => 19;

  my $c = npg_pipeline::function::warehouse_archiver->new(
    run_folder          => q{123456_IL2_1234},
    runfolder_path      => $runfolder_path,
    recalibrated_path   => $runfolder_path,
    resource            => $default
  );
  isa_ok ($c, 'npg_pipeline::function::warehouse_archiver');

  my $recalibrated_path = $c->recalibrated_path();
  my $recalibrated_path_in_outgoing = $recalibrated_path;
  $recalibrated_path_in_outgoing =~ s{/analysis/}{/outgoing/}smx;


  foreach my $m (@wh_methods) {

    my $postqcc  = $m =~ /$pqq_suffix/smx;
    my $command  = 'npg_runs2mlwarehouse';
    my $job_name = $command . '_1234_pname';
    $command    .= ' --verbose --id_run 1234';
    if ($postqcc) {
      $job_name .= '_postqccomplete';
    } else {
      $command .= ' && npg_run_params2mlwarehouse --id_run 1234 --path_glob ' .
        "'$runfolder_path/{r,R}unParameters.xml'";
    }

    my $ds = $c->$m('pname');
    ok ($ds && scalar @{$ds} == 1 && !$ds->[0]->excluded,
      'update to warehouse is enabled');
    my $d = $ds->[0];
    isa_ok ($d, 'npg_pipeline::function::definition');

    is ($d->identifier, '1234', 'identifier set to run id');
    is ($d->created_by, 'npg_pipeline::function::warehouse_archiver', 'created_by');
    is ($d->command, $command, "command for $m");
    is ($d->job_name, $job_name, "job name for $m");
    is ($d->queue, 'lowload', 'queue');
    is_deeply ($d->num_cpus, [0], 'zero CPUs required');
    ok (!$d->has_command_preexec, "preexec command not defined for $m");
  }
};

subtest 'warehouse updates disabled' => sub {
  plan tests => 6;

  my $test_method = sub {
    my ($f, $method, $switch) = @_;
    my $d = $f->$method();
    ok($d && scalar @{$d} == 1 &&
      ($switch eq 'off' ? $d->[0]->excluded : !$d->[0]->excluded),
      $method . ': update to warehouse switched ' . $switch);
  };

  foreach my $m (@wh_methods) {
    my $c = npg_pipeline::function::warehouse_archiver->new(
      runfolder_path      => $runfolder_path,
      no_warehouse_update => 1,
      resource            => $default
    );
    $test_method->($c, $m, 'off');

    $c = npg_pipeline::function::warehouse_archiver->new(
      runfolder_path    => $runfolder_path,
      local             => 1,
      resource          => $default
    );
    $test_method->($c, $m, 'off');

    $c = npg_pipeline::function::warehouse_archiver->new(
      runfolder_path      => $runfolder_path,
      local               => 1,
      no_warehouse_update => 0,
      resource            => $default
    );
    $test_method->($c, $m, 'on');
  }
};

subtest 'mlwh updates for a product' => sub {
  plan tests => 7;

  my $wa = npg_pipeline::function::warehouse_archiver->new(
    runfolder_path    => $runfolder_path,
    label             => 'my_label',
    product_rpt_list  => '123:4:5',
    resource          => $default
  );

  my $ds = $wa->update_ml_warehouse('pname');
  ok ($ds && scalar @{$ds} == 1 && !$ds->[0]->excluded,
    'update to warehouse is enabled');
  my $d = $ds->[0];
  isa_ok ($d, 'npg_pipeline::function::definition');
  is ($d->identifier, 'my_label', 'identifier set to the label value');
  is ($d->command,
    "npg_products2mlwarehouse --verbose --rpt_list '123:4:5'", 'command');
  is ($d->job_name, 'npg_runs2mlwarehouse_my_label_pname', 'job name');
  is ($d->queue, 'lowload', 'queue');
  is_deeply ($d->num_cpus, [0], 'zero CPUs required');
};

1;

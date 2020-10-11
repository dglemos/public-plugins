=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EnsEMBL::Web::RunnableDB::VR;

### Hive Process RunnableDB for VR

use strict;
use warnings;

use parent qw(EnsEMBL::Web::RunnableDB);

use EnsEMBL::Web::Exceptions;
use EnsEMBL::Web::SystemCommand;
use EnsEMBL::Web::Utils::FileHandler qw(file_append_contents);
use Bio::EnsEMBL::VEP::VariantRecoder;
use FileHandle;

use Data::Dumper;

sub fetch_input {
  my $self = shift;

  # required params
  $self->param_required($_) for qw(work_dir config job_id);
}

sub run {
  my $self = shift;

  my $work_dir        = $self->param('work_dir');
  my $config          = $self->param('config');
  my $options         = $self->param('script_options') || {};
  my $log_file        = "$work_dir/lsf_log.txt";

  $options->{$_}  = 1 for qw(force quiet safe); # we need these options set on always!
  $options->{$_}  = sprintf '%s/%s', $work_dir, delete $config->{$_} for qw(input_file output_file);
  $options->{$_}  = $config->{$_} eq 'yes' ? 1 : $config->{$_} for grep { defined $config->{$_} && $config->{$_} ne 'no' } keys %$config;
  $options->{output_file} = $work_dir . '/output_file'; 

  # NOT SURE IS NECESSARY
  $options->{"database"} = 1;
  $options->{"db_version"} = 101; # DELETE
  
  # send warnings to STDERR
  # $options->{"warning_file"} = "STDERR";

  # save the result file name for later use
  $self->param('result_file', $options->{'output_file'});
  
  # set reconnect_when_lost()
  my $reconnect_when_lost_bak = $self->dbc->reconnect_when_lost;
  $self->dbc->reconnect_when_lost(1);

  $self->warning(Dumper $options);

  # create a Variant Recoder runner and run the job
  my $runner = Bio::EnsEMBL::VEP::VariantRecoder->new($options);
  my $results = $runner->recode_all;

  my $json = JSON->new;
  $json->pretty;

  my $print_input = '';
  foreach my $result_hash (@$results) {
    my @keys = keys %{$result_hash};
    foreach my $allele (@keys) {
      my $allele_result = $result_hash->{$allele};
      my $hgvsg_print = join(', ', @{$allele_result->{'hgvsg'}});
      my $hgvsc_print = join(', ', @{$allele_result->{'hgvsc'}});
      my $hgvsp_print = join(', ', @{$allele_result->{'hgvsp'}});
      my $spdi_print = join(', ', @{$allele_result->{'spdi'}});
      my $id_print = join(', ', @{$allele_result->{'id'}});
      my $vcf_print = join(', ', @{$allele_result->{'vcf_string'}});
      $print_input = $allele."\t".$allele_result->{'input'}."\t".$hgvsg_print."\t".$hgvsc_print."\t".$hgvsp_print."\t".$spdi_print."\t".$id_print."\t".$vcf_print."\n";
    }
  }

  my $fh = FileHandle->new("$work_dir/output_test", 'w');
  print $fh $print_input;
  $fh->close();

  # file_append_contents($options->{output_file}, $json->encode($results));

  # EXAMPLE
  my $fh = FileHandle->new("$work_dir/output_test", 'w');
  print $fh "rs699\tENST00000366667.5:c.803T>C\tNC_000001.11:230710047:A:G\tRCV000835695\n";
  $fh->close();

  # restore reconnect_when_lost()
  $self->dbc->reconnect_when_lost($reconnect_when_lost_bak);

  return 1;
}

sub write_output {
  my $self        = shift;
  my $job_id      = $self->param('job_id');

  return 1;
}

1;

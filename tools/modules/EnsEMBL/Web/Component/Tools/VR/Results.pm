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

package EnsEMBL::Web::Component::Tools::VR::Results;

use strict;
use warnings;


use parent qw(EnsEMBL::Web::Component::Tools::VR);

use EnsEMBL::Web::Utils::FileHandler qw(file_get_contents);

sub content {
  my $self    = shift;
  my $hub     = $self->hub;
  my $sd      = $hub->species_defs;
  my $object  = $self->object;
  my $ticket  = $object->get_requested_ticket;
  my $job     = $ticket ? $ticket->job->[0] : undef;

  my $job_data  = $job->job_data;
  my $job_config  = $job->dispatcher_data->{'config'};

  my $output_file  = 'output_test';

  my @rows;
  my @headers = qw/input hgvs spdi id/;

  my @content = file_get_contents(join('/', $job->job_dir, $output_file), sub { s/\R/\r\n/r });


  my @rows = ();
  foreach my $line (@content) {
    chomp $line;
    my @split     = split /\t/, $line;
    my %row_data  = map { $headers[$_] => $split[$_] } 0..$#headers;
    push @rows, \%row_data;
  }  

  my @table_headers = map {{
      'key' => $_,
      'title' => $_,
      'sort' => 'string',
  }} @headers;

  my $table = $self->new_table(\@table_headers, \@rows, { data_table => 1, exportable => 0, data_table_config => {bLengthChange => 'false', bFilter => 'false'}, });
  my $html .= $table->render || '<h3>No data</h3>';

  return $html;
}
1;

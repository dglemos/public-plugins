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

use EnsEMBL::Web::Utils::FileHandler qw(file_get_contents);
use EnsEMBL::Web::Component::Tools::NewJobButton;

use parent qw(EnsEMBL::Web::Component::Tools::VR);

sub content {
  my $self    = shift;
  my $hub     = $self->hub;
  my $sd      = $hub->species_defs;
  my $object  = $self->object;
  my $ticket  = $object->get_requested_ticket;
  my $job     = $ticket ? $ticket->job->[0] : undef;

  return '' if !$job || $job->status ne 'done';

  my $job_data  = $job->job_data;
  my $job_config  = $job->dispatcher_data->{'config'};
  my $species   = $job->species;

  my $ticket_name = $object->parse_url_param->{'ticket_name'};

  my $button_url = $hub->url({'function' => undef, 'expand_form' => 'true'});
  my $new_job_button = EnsEMBL::Web::Component::Tools::NewJobButton->create_button( $button_url );

  # THIS OUTPUT IS DEFINED IN THE RUNNABLE
  my $output_file  = 'output_test';
  my $output_file_json = 'output_file.json';

  my $result_headers = $job_config->{'result_headers'};
  my @headers = @$result_headers;

  # From output file in tab format
  my @content = file_get_contents(join('/', $job->job_dir, $output_file), sub { s/\R/\r\n/r });

  # Download
  my $html = '';
  if (scalar @content) {
    my $down_url  = $object->download_url({output_file => $output_file});
    $html .= qq{<p><div class="component-tools tool_buttons"><a class="export" href="$down_url">Download all results</a><div class="left-margin">$new_job_button</div></div></p>};
  }

  my @rows = ();
  foreach my $line (@content) {
    chomp $line;
    my @split     = split /\t/, $line;
    my %row_data  = map { $headers[$_] => $split[$_] } 0..$#headers;
    push @rows, \%row_data;
  }

  # linkify row content
  my $row_id = 0;
  foreach my $row (@rows) {
    foreach my $header (@headers) {
      if ($row->{$header} && $row->{$header} ne '' && $row->{$header} ne '-') {
        if ($header eq 'id') {
          $row->{$header} = $self->get_items_in_list($row_id, 'id', 'Variant identifier', $row->{$header}, $species);
        }
        elsif ($header eq 'hgvsc') {
          $row->{$header} = $self->linkify($header, $row->{$header}, $species, $job_data);
        }
      }
      $row_id++;
    }
  }

  # niceify for table
  my %header_titles = (
    'id'                  => 'Variant identifier',
    'hgvsg'               => 'HGVS genomic',
    'hgvsc'               => 'HGVS transcript',
    'hgvsp'               => 'HGVS protein',
    'vcf_format'          => 'VCF format',
    'spdi'                => 'SPDI',
    'allele'              => 'Allele',
    'input'               => 'Uploaded variant'
  );
  for (grep {/\_/} @headers) {
    $header_titles{$_} ||= $_ =~ s/\_/ /gr;
  }

  my @table_headers = map {{
    'key' => $_,
    'title' => ($header_titles{$_} || $_),
    'sort' => 'string',
  }} @headers;

  my $table = $self->new_table(\@table_headers, \@rows, { data_table => 1, exportable => 0, data_table_config => {bLengthChange => 'false', bFilter => 'false'}, });
  $html .= $table->render || '<h3>No data</h3>';

  # close toolboxes container div
  $html .= '</div>';

  return $html;
}

sub linkify {
  my $self = shift;
  my $field = shift;
  my $values = shift;
  my $species = shift;
  my $job_data = shift;

  # work out core DB type
  my $db_type = 'core';
  if(my $ct = $job_data->{core_type}) {
    if($ct eq 'refseq' || ($values && $ct eq 'merged' && $values !~ /^ENS/)) {
      $db_type = 'otherfeatures';
    }
  }

  my @return_values = ();
  my $new_value;
  my $hub = $self->hub;
  my $sd = $hub->species_defs;

  my @all_values = split(', ', $values);

  foreach my $value (@all_values) {

  return '-' unless defined $value && $value ne '';

  # transcript
  if($field eq 'hgvsc' && $value =~ /^ENS/) {

    my @split_value = split(':', $value);

    my $url = $hub->url({
      type    => 'Transcript',
      action  => 'Summary',
      t       => $split_value[0],
      species => $species,
      db      => $db_type,
    });

    my $zmenu_url = $hub->url({
      type    => 'ZMenu',
      action  => 'Transcript',
      t       => $split_value[0],
      species => $species,
      db      => $db_type,
    });

    $new_value = $self->zmenu_link($url, $zmenu_url, $split_value[0]);
    $new_value .= ":".$split_value[1];
  }

  else {
    $new_value = defined($value) && $value ne '' ? $value : '-';
  }

  push @return_values, $new_value;

  }

  return join('<br />', @return_values);
}


# Get a list of comma separated items and transforms it into a bullet point list
sub get_items_in_list {
  my $self    = shift;
  my $row_id  = shift;
  my $type    = shift;
  my $label   = shift;
  my $data    = shift;
  my $species = shift;
  my $min_items_count = shift;

  my $hub = $self->hub;

  $min_items_count ||= 5;

  my @items_list = split(', ',$data);
  my @items_with_url;

  if ($type eq 'id') {
    foreach my $item (@items_list) {
      my $item_url = $item;
      if($item =~ /^rs/) {
        $item_url = $hub->get_ExtURL_link($item, 'DBSNP', $item);
      }
      if($item =~ /^COS/) {
        $item_url = $hub->get_ExtURL_link($item, 'COSMIC', $item);
      }
      if($item =~ /^CM/) {
        $item_url = $hub->get_ExtURL_link($item, 'HGMD-PUBLIC', $item);
      }
      push(@items_with_url, $item_url);
    }
  }

  if (scalar @items_list > $min_items_count) {
    my $div_id = 'row_'.$row_id.'_'.$type;
    return $self->display_items_list($div_id, $type, $label, \@items_with_url, \@items_list);
  }
  else {
    return join('<br />',@items_with_url);
  }
}

sub zmenu_link {
  my ($self, $url, $zmenu_url, $html) = @_;

  return sprintf('<a class="_zmenu" href="%s">%s</a><a class="hidden _zmenu_link" href="%s"></a>', $url, $html, $zmenu_url);
}

1;

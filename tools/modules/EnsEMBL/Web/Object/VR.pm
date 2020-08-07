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

package EnsEMBL::Web::Object::VR;

use strict;
use warnings;

use HTML::Entities  qw(encode_entities);

use EnsEMBL::Web::TmpFile::ToolsOutput;
use EnsEMBL::Web::TmpFile::VcfTabix;
use EnsEMBL::Web::Utils::FileHandler qw(file_get_contents);
use Bio::EnsEMBL::Variation::Utils::Constants;
use Bio::EnsEMBL::Variation::Utils::VariationEffect;

use parent qw(EnsEMBL::Web::Object::Tools);

sub tab_caption {
  ## @override
  return 'VR';
}

sub valid_species {
  ## @override
  my $self = shift;
  return $self->hub->species_defs->reference_species($self->SUPER::valid_species(@_));
}

sub get_edit_jobs_data {
  ## Abstract method implementation
  my $self        = shift;
  my $hub         = $self->hub;
  my $ticket      = $self->get_requested_ticket   or return [];
  my $job         = shift @{ $ticket->job || [] } or return [];
  my $job_data    = $job->job_data->raw;
  my $input_file  = sprintf '%s/%s', $job->job_dir, $job_data->{'input_file'};

  if (-T $input_file && $input_file !~ /\.gz$/ && $input_file !~ /\.zip$/) { # TODO - check if the file is binary!
    if (-s $input_file <= 1024) {
      $job_data->{"text"} = file_get_contents($input_file);
    } else {
      $job_data->{'input_file_type'}  = 'text';
      $job_data->{'input_file_url'}   = $self->download_url({'input' => 1});
    }
  } else {
    $job_data->{'input_file_type'} = 'binary';
  }

  return [ $job_data ];
}

sub result_files {
  ## Gets the result stats and ouput files
  my $self = shift;

  if (!$self->{'_results_files'}) {
    my $ticket      = $self->get_requested_ticket or return;
    my $job         = $ticket->job->[0] or return;
    my $job_config  = $job->dispatcher_data->{'config'};
    my $job_dir     = $job->job_dir;

    $self->{'_results_files'} = {
      'output_file' => EnsEMBL::Web::TmpFile::VcfTabix->new('filename' => "$job_dir/$job_config->{'output_file'}")
    };
  }

  return $self->{'_results_files'};
}

sub get_all_variants_in_slice_region {
  ## Gets all the result variants for the given job in the given slice region
  ## @param Job object
  ## @param Slice object
  ## @return Array of result data hashrefs
  my ($self, $job, $slice) = @_;

  my $ticket_name = $job->ticket->ticket_name;
  my $job_id      = $job->job_id;
  my $s_name      = $slice->seq_region_name;
  my $s_start     = $slice->start;
  my $s_end       = $slice->end;

  my @variants;

  for ($job->result) {

    my $var   = $_->result_data->raw;
    my $chr   = $var->{'chr'};
    my $start = $var->{'start'};
    my $end   = $var->{'end'};

    next unless $s_name eq $chr && (
      $start >= $s_start && $end <= $s_end ||
      $start < $s_start && $end <= $s_end && $end > $s_start ||
      $start >= $s_start && $start <= $s_end && $end > $s_end ||
      $start < $s_start && $end > $s_end && $start < $s_end
    );

    $var->{'tl'} = $self->create_url_param({'ticket_name' => $ticket_name, 'job_id' => $job_id, 'result_id' => $_->result_id});

    push @variants, $var;

  };

  return \@variants;
}

sub handle_download {
  my ($self, $r) = @_;

  my $hub = $self->hub;
  my $job = $self->get_requested_job;

  # if downloading the input file
  if ($hub->param('input')) {

    my $filename  = $job->job_data->{'input_file'};
    my $content   = file_get_contents(join('/', $job->job_dir, $filename), sub { s/\R/\r\n/r });

    $r->headers_out->add('Content-Type'         => 'text/plain');
    $r->headers_out->add('Content-Length'       => length $content);
    $r->headers_out->add('Content-Disposition'  => sprintf 'attachment; filename=%s', $filename);

    print $content;

  # if downloading the result file in any specified format
  } else { 
    my $format    = $hub->param('format')   || 'vcf';
    my $location  = $hub->param('location') || '';
    my $filter    = $hub->param('filter')   || '';
    my $file      = $self->result_files->{'output_file'};
    my $filename  = join('.', $job->ticket->ticket_name, $location || (), $filter || (), $format eq 'txt' ? () : $format, $format eq 'vcf' ? '' : 'txt') =~ s/\s+/\_/gr;

    $r->headers_out->add('Content-Type'         => 'text/plain');
    $r->headers_out->add('Content-Disposition'  => sprintf 'attachment; filename=%s', $filename);

    $file->content_iterate({'format' => $format, 'location' => $location, 'filter' => $filter}, sub {
      print "$_\r\n" for @_;
      $r->rflush;
    });
  }
}

sub get_form_details {
  my $self = shift;

  if(!exists($self->{_form_details})) {

    $self->{_form_details} = {
      input_type => {
        'label' => 'Input data type',
        'values' => [
          { 'value' => 'id', 'caption' => 'Variant identifier (Examples: )' },
          { 'value' => 'spdi', 'caption' => 'Genomic SPDI' },
          { 'value' => 'hgvsg', 'caption' => 'HGVS Genomic' },
          { 'value' => 'hgvsp', 'caption' => 'HGVS Coding' },
          { 'value' => 'hgvsc', 'caption' => 'HGVS Protein' },
        ]},
      variant_option => {
        'label' => 'Variant option',
        'values' => [
          { 'value' => 'single', 'caption' => 'Query a single variant' },
          { 'value' => 'multi', 'caption' => 'Query multiple variants' },
        ]},
        id => {
          'label'   => 'Variant identifier',
          'helptip' => '',
        },
        spdi => {
          'label'   => 'Genomic SPDI',
          'helptip' => '',
        },
        hgvsg => {
          'label'   => 'HGVS Genomic',
          'helptip' => '',
        },
        hgvsc => {
          'label'   => 'HGVS Coding',
          'helptip' => '',
        },
        hgvsp => {
          'label'   => 'HGVS Protein',
          'helptip' => '',
        },
        vcf_string => {
          'label'   => 'VCF format',
          'helptip' => '',
        },
    };
  }

  return $self->{_form_details};
}

sub get_consequences_data {
  ## Gets overlap consequences information needed to render preview
  ## @return Hashref with keys as consequence types
  my $self  = shift;
  my $hub   = $self->hub;
  my $cm    = $hub->colourmap;
  my $sd    = $hub->species_defs;

  my %cons = map {$_->{'SO_term'} => {
    'description' => $_->{'description'},
    'rank'        => $_->{'rank'},
    'colour'      => $cm->hex_by_name($sd->colour('variation')->{lc $_->{'SO_term'}}->{'default'})
  }} values %Bio::EnsEMBL::Variation::Utils::Constants::OVERLAP_CONSEQUENCES;

  return \%cons;
}

sub species_list {
  ## Returns a list of species with VEP specific info
  ## @return Arrayref of hashes with each hash having species specific info
  my $self = shift;

  if (!$self->{'_species_list'}) {
    my $hub     = $self->hub;
    my $sd      = $hub->species_defs;

    my @species;

    for ($self->valid_species) {

      # Ignore any species with VEP disabled
      next if ($sd->get_config($_, 'VEP_DISABLED'));

      my $db_config = $sd->get_config($_, 'databases');

      # example data for each species
      my $sample_data   = $sd->get_config($_, 'SAMPLE_DATA');
      my $example_data  = {};
      for (grep m/^VEP/, keys %$sample_data) {
        $example_data->{lc s/^VEP\_//r} = $sample_data->{$_};
      }

      push @species, {
        'value'       => $_,
        'caption'     => $sd->species_label($_, 1),
        'variation'   => $db_config->{'DATABASE_VARIATION'} // undef,
        'refseq'      => $db_config->{'DATABASE_OTHERFEATURES'} && $sd->get_config($_, 'VEP_REFSEQ') // undef,
        'assembly'    => $sd->get_config($_, 'ASSEMBLY_NAME') // undef,
        'example'     => $example_data,
      };
    }

    @species = sort { $a->{'caption'} cmp $b->{'caption'} } @species;

    $self->{'_species_list'} = \@species;
  }

  return $self->{'_species_list'};
}

1;

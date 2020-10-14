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

package EnsEMBL::Web::Component::Tools::VR::InputForm;

use strict;
use warnings;

use EnsEMBL::Web::VRConstants qw(INPUT_FORMATS);

use parent qw(
  EnsEMBL::Web::Component::Tools::VR
  EnsEMBL::Web::Component::Tools::InputForm
);

sub form_header_info {
  ## Abstract method implementation
  my $self = shift;

  return $self->tool_header({'reset' => 'Clear form', 'cancel' => 'Close'});
}

sub get_cacheable_form_node {
  ## Abstract method implementation
  my $self            = shift;
  my $hub             = $self->hub;
  my $object          = $self->object;
  my $sd              = $hub->species_defs;
  my $species         = $object->species_list;
  # my $form            = $self->new_tool_form({'class' => 'vep-form'}); # from VEP
  my $form            = $self->new_tool_form; # from LD
  my $fd              = $object->get_form_details;
  my $input_formats   = INPUT_FORMATS;
  my $input_fieldset  = $form->add_fieldset({'no_required_notes' => 1});
  my $current_species = $self->current_species;
  my $msg             = $self->species_specific_info($self->current_species, 'VR', 'VR', 1);

  my ($current_species_data)  = grep { $_->{value} eq $current_species } @$species;
  my @available_input_formats = grep { $current_species_data->{example}->{$_->{value}} } @$input_formats;


  # Species dropdown list with stt classes to dynamically toggle other fields
  $input_fieldset->add_field({
    'label'         => 'Species',
    'elements'      => [{
      'type'          => 'speciesdropdown',
      'name'          => 'species',
      'values'        => [ map {
        'value'         => $_->{'value'},
        'caption'       => $_->{'caption'},
        'class'         => [  #selectToToggle classes for JavaScript
          '_stt', '_sttmulti',
          $_->{'variation'}             ? '_stt__var'   : '_stt__novar',
          $_->{'refseq'}                ? '_stt__rfq'   : (),
        ]
      }, @$species ]
    }, {
      'type'          => 'noedit',
      'value'         => 'Assembly: '. join('', map { sprintf '<span class="_stt_%s _vep_assembly" rel="%s">%s</span>', $_->{'value'}, $_->{'assembly'}, $_->{'assembly'} } @$species).'<span class="_msg _stt_Homo_sapiens italic"> ('.$msg.')</span>',
      'no_input'      => 1,
      'is_html'       => 1
    }]
  });

  $input_fieldset->add_field({
    'type'          => 'string',
    'name'          => 'name',
    'label'         => 'Name for this job (optional)'
  });

  $input_fieldset->add_field({
      'type'          => 'radiolist',
      'name'          => 'variant_option',
      'label'         => $fd->{variant_option}->{label},
      # 'helptip'       => $fd->{id}->{helptip},
      'value'         => 'region',
      'class'         => '_stt',
      'values'        => $fd->{variant_option}->{values}
  });

  $input_fieldset->add_field({
      'type'          => 'radiolist',
      'name'          => 'input_type',
      'label'         => $fd->{input_type}->{label},
      # 'helptip'       => $fd->{id}->{helptip},
      'value'         => 'region',
      'class'         => '_stt',
      'values'        => $fd->{input_type}->{values}
  });

  $input_fieldset->add_field({
    'label'         => 'Input data',
    'elements'      => [
      {
        'type'          => 'noedit',
        'value'         => '<b>Either paste data:</b>',
        'no_input'      => 1,
        'is_html'       => 1,
      },
      {
       'type'          => 'text',
       'name'          => 'text',
       'class'         => 'vep-input',
      },
      add_example_links(\@available_input_formats),
      {
        'type'          => 'div',
        'element_class' => 'vep_left_input',
        'inline'        => 1,
        'children'      => [{
          'node_name'   => 'span',
          'class'       => '_ht ht',
          'title'       => sprintf('File uploads are limited to %sMB in size.', $sd->ENSEMBL_TOOLS_CGI_POST_MAX->{'VEP'} / (1024 * 1024)),
          'inner_HTML'  => '<b>Or upload file:</b>'
        }]
      },
      {
        'type'            => 'file',
        'name'            => 'file',
      }]
  });

  $input_fieldset->add_field({
    'type'          => 'checklist',
    'label'         => 'Results',
    'field_class'   => [qw(_stt_yes _stt_allele)],
    'values'        => [{
      'name'          => "id",
      'caption'       => $fd->{id}->{label},
      # 'helptip'       => $fd->{af}->{helptip},
      'value'         => 'yes',
      'checked'       => 1
    }, {
      'name'          => "spdi",
      'caption'       => $fd->{spdi}->{label},
      # 'helptip'       => $fd->{af_1kg}->{helptip},
      'value'         => 'yes',
      'checked'       => 1
    }, {
      'name'          => "hgvsg",
      'caption'       => $fd->{hgvsg}->{label},
      # 'helptip'       => $fd->{af_esp}->{helptip},
      'value'         => 'yes',
      'checked'       => 1
    }, {
      'name'          => "hgvsc",
      'caption'       => $fd->{hgvsc}->{label},
      # 'helptip'       => $fd->{af_gnomad}->{helptip},
      'value'         => 'yes',
      'checked'       => 1
    }, {
      'name'          => "hgvsp",
      'caption'       => $fd->{hgvsp}->{label},
      # 'helptip'       => $fd->{af_gnomad}->{helptip},
      'value'         => 'yes',
      'checked'       => 1
    }, {
      'name'          => "vcf_string",
      'caption'       => $fd->{vcf_string}->{label},
      # 'helptip'       => $fd->{af_gnomad}->{helptip},
      'value'         => 'yes',
      'checked'       => 1
    }]
  }),

  # Run button
  $self->add_buttons_fieldset($form);

  return $form;
}

sub add_example_links {
  my $input_formats = shift;

  if ($#$input_formats >= 0) {
    return {
      'type'    => 'noedit',
      'noinput' => 1,
      'is_html' => 1,
      'caption' => sprintf('<span class="small"><b>Examples:&nbsp;</b>%s</span>',
        join(', ', (map { sprintf('<a href="#" class="_example_input" rel="%s">%s</a>', $_->{'value'}, $_->{'caption'}) } @$input_formats ))
      )
    }
  }
  return;
}
sub get_non_cacheable_fields {
  ## Abstract method implementation
  return {};
}

sub js_panel {
  ## @override
  return 'VEPForm';
}

sub js_params {
  ## @override
  my $self    = shift;
  my $hub     = $self->hub;
  my $object  = $self->object;
  my $species = $object->species_list;
  my $params  = $self->SUPER::js_params(@_);

  # example data for each species
  $params->{'example_data'} = { map { $_->{'value'} => delete $_->{'example'} } @$species };

  # REST server address for VEP preview
  $params->{'rest_server_url'} = $hub->species_defs->ENSEMBL_REST_URL;

  return $params;
}

sub _build_identifiers {
  my ($self, $form) = @_;

  my $hub       = $self->hub;
  my $object    = $self->object;
  my $species   = $object->species_list;
  my $fd        = $object->get_form_details;

  my @fieldsets;

  ## IDENTIFIERS
  my $current_section = 'Identifiers';
  my $fieldset        = $form->add_fieldset({'legend' => $current_section, 'no_required_notes' => 1});

  $fieldset->add_field({
    'type'        => 'checkbox',
    'name'        => 'id',
    'label'       => $fd->{id}->{label},
    'helptip'     => $fd->{id}->{helptip},
    'value'       => 'yes',
    'checked'     => 1
  });

  $fieldset->add_field({
    'type'        => 'checkbox',
    'name'        => 'hgvsg',
    'label'       => $fd->{hgvsg}->{label},
    'helptip'     => $fd->{hgvsg}->{helptip},
    'value'       => 'yes'
  });

  $fieldset->add_field({
    'type'        => 'checkbox',
    'name'        => 'hgvsc',
    'label'       => $fd->{hgvsc}->{label},
    'helptip'     => $fd->{hgvsc}->{helptip},
    'value'       => 'yes'
  });

  $fieldset->add_field({
    'type'        => 'checkbox',
    'name'        => 'hgvsp',
    'label'       => $fd->{hgvsp}->{label},
    'helptip'     => $fd->{hgvsp}->{helptip},
    'value'       => 'yes'
  });

  $fieldset->add_field({
    'type'        => 'checkbox',
    'name'        => 'spdi',
    'label'       => $fd->{spdi}->{label},
    'helptip'     => $fd->{spdi}->{helptip},
    'value'       => 'yes'
  });

  $fieldset->add_field({
    'type'        => 'checkbox',
    'name'        => 'vcf_string',
    'label'       => $fd->{vcf_string}->{label},
    'helptip'     => $fd->{vcf_string}->{helptip},
    'value'       => 'yes'
  });

  $self->_end_section(\@fieldsets, $fieldset, $current_section);

  return @fieldsets;
}

sub _end_section {
  my ($self, $fieldsets, $fieldset, $section) = @_;

  push @$fieldsets, $fieldset;

  $self->{_done_sections}->{$section} = 1;
}

1;

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

  $options->{$_}  = sprintf '%s/%s', $work_dir, delete $config->{$_} for qw(input_file output_file);
  $options->{$_}  = $config->{$_} eq 'yes' ? 1 : $config->{$_} for grep { defined $config->{$_} && $config->{$_} ne 'no' } keys %$config;
  $options->{output_file} = $work_dir . '/vr_output.json'; 

  $options->{"db_version"} = 101; # DELETE

  # Header contains: allele, input and the fields
  my $result_headers = $config->{'result_headers'};
  my @fields = @$result_headers;
  # Remove allele and input from list - remove vcf_string (in case it's there)
  for my $i (reverse 0..$#fields) {
    if ( $fields[$i] =~ /allele/ || $fields[$i] =~ /input/ || $fields[$i] =~ /vcf_string/) {
        splice(@fields, $i, 1, ());
    }
  }

  # Add vcf_string to the fields - need vcf_string to be able to download a VCF file
  push @fields, 'vcf_string';

  $options->{'fields'} = join(',', @fields);

  # set reconnect_when_lost()
  my $reconnect_when_lost_bak = $self->dbc->reconnect_when_lost;
  $self->dbc->reconnect_when_lost(1);

  $self->warning(Dumper $options);

  my $input_size = $config->{'input_size'};
  if($input_size == 1) {
  
  }

  # create a Variant Recoder runner and run the job
  my $runner = Bio::EnsEMBL::VEP::VariantRecoder->new($options);
  my $results = $runner->recode_all;

  my @vcf_result;
  # Write VCF output header
  push @vcf_result, "##INFO=HGVSg,Description=\"HGVS Genomic\">";
  push @vcf_result, "##INFO=HGVSc,Description=\"HGVS Transcript\">";
  push @vcf_result, "##INFO=HGVSp,Description=\"HGVS Protein\">";
  push @vcf_result, "##INFO=SPDI,Description=\"SPDI\">";
  push @vcf_result, "##INFO=VARID,Description=\"Variant identifier\">";
  push @vcf_result, "##INFO=VCF,Description=\"VCF string\">";
  push @vcf_result, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO";

  my @print_output = ();
  foreach my $result_hash (@$results) {
    my @keys = keys %{$result_hash};
    foreach my $allele (@keys) {
      my $vcf_variant_info = '';

      my $allele_result = $result_hash->{$allele};
      my $print_input = $allele_result->{'input'}."\t".$allele;

      if($config->{'hgvsg'} eq 'yes') {
        my $join_result = join(', ', @{$allele_result->{'hgvsg'}});
        $print_input = $print_input."\t".$join_result;
        # VCF
        $join_result =~ s/ //g;
        $vcf_variant_info .= "HGVSg=$join_result;";
      }
      if($config->{'hgvsc'} eq 'yes') {
        if($allele_result->{'hgvsc'}) {
          my $join_result = join(', ', @{$allele_result->{'hgvsc'}});
          $print_input = $print_input."\t".$join_result;
          # VCF
          $join_result =~ s/ //g;
          $vcf_variant_info .= "HGVSc=$join_result;";
        }
        else {
          $print_input = $print_input."\t-";
        }
      }
      if($config->{'hgvsp'} eq 'yes') {
        if($allele_result->{'hgvsp'}) {
          my $join_result = join(', ', @{$allele_result->{'hgvsp'}});
          $print_input = $print_input."\t".$join_result;
          # VCF
          $join_result =~ s/ //g;
          $vcf_variant_info .= "HGVSp=$join_result;";
        }
        else {
          $print_input = $print_input."\t-";
        }
      }
      if($config->{'spdi'} eq 'yes') {
        my $join_result = join(', ', @{$allele_result->{'spdi'}});
        $print_input = $print_input."\t".$join_result;
        # VCF
        $join_result =~ s/ //g;
        $vcf_variant_info .= "SPDI=$join_result;";
      }
      if($config->{'id'} eq 'yes') {
        if($allele_result->{'id'}) {
         my $join_result = join(', ', @{$allele_result->{'id'}});
         $print_input = $print_input."\t".$join_result;
         # VCF
         $join_result =~ s/ //g;
         $vcf_variant_info .= "VARID=$join_result;";
        }
        else {
          $print_input = $print_input."\t-";
        }
      }
      if($config->{'vcf_string'} eq 'yes') {
        if($allele_result->{'vcf_string'}) {
          my $join_result = join(', ', @{$allele_result->{'vcf_string'}});
          $print_input = $print_input."\t".$join_result;
          # VCF
          $join_result =~ s/ //g;
          $vcf_variant_info .= "VCF=$join_result;";
 
          foreach my $result (@{$allele_result->{'vcf_string'}}) {
           my @result_split = split /-/, $result;
           my $vcf_variant = $result_split[0] . "\t" . $result_split[1] . "\t\.\t" . $result_split[2] . "\t" . $result_split[3] . "\t.\t\.\t";
           if($vcf_variant_info eq '') {
             $vcf_variant .= ".";
           }
           else {
             $vcf_variant .= $vcf_variant_info;
           }
           push @vcf_result, $vcf_variant;
          }
        }
        else {
          $print_input = $print_input."\t-";
        }
      }
      push @print_output, $print_input;
    }
  }

  my $fh = FileHandle->new("$work_dir/output_test", 'w');
  # Write output - VCF format
  my $fh_vcf = FileHandle->new("$work_dir/vr_output.vcf", 'w');
  print $fh_vcf join("\n", @vcf_result);
  $fh_vcf->close();

  # Write output - TXT format
  my $fh = FileHandle->new("$work_dir/vr_output", 'w');
  print $fh join("\n", @print_output);
  $fh->close();

  # Write output - JSON format
  my $json = JSON->new;
  $json->pretty;
  file_append_contents($options->{output_file}, $json->encode($results));

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

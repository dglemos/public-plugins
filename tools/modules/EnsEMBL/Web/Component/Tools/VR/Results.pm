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
use POSIX qw(ceil);
use EnsEMBL::Web::Utils::FormatText qw(helptip);

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

  # niceify for table
  my %header_titles = (
    'id'                  => 'Variant identifier',
    'hgvsg'               => 'HGVS Genomic',
    'hgvsc'               => 'HGVS Transcript',
    'hgvsp'               => 'HGVS Protein',
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

  my $line_count = scalar(@rows);
  my $from = 1;
  my $actual_to = $from - 1 + ($line_count || 0);

  my $nav_html = $self->_navigation($actual_to, $line_count);
  $html .= '<div class="toolbox right-margin">';
  $html .= '<div class="toolbox-head">';
  $html .= '<img src="/i/16/eye.png" style="vertical-align:top;"> ';
  $html .= helptip('Navigation', "Navigate through the results of your Variant Recoder job. By default the results for 5 variants are displayed.");
  $html .= '</div>';
  $html .= '<div style="padding:5px;">'.$nav_html.'</div>';
  $html .= '</div>';

  # these are framed within the subroutine
  my ($filter_html, $active_filters) = @{$self->_filters($result_headers, \%header_titles)};
  $html .= $filter_html;

  # linkify row content
  my $row_id = 0;
  foreach my $row (@rows) {
    foreach my $header (@headers) {
      if ($row->{$header} && $row->{$header} ne '' && $row->{$header} ne '-') {
        if ($header eq 'id') {
          $row->{$header} = $self->get_items_in_list($row_id, 'id', 'Variant identifier', $row->{$header}, $species);
        }
        elsif ($header eq 'vcf_string') {
          $row->{$header} = $self->get_items_in_list($row_id, 'vcf_string', 'VCF format', $row->{$header}, $species);
        }
        elsif ($header eq 'hgvsc' || $header eq 'hgvsp' || $header eq 'spdi' || $header eq 'hgvsg') {
          $row->{$header} = $self->linkify($header, $row->{$header}, $species, $job_data);
        }
      }
      $row_id++;
    }
  }

  my $table = $self->new_table(\@table_headers, \@rows, { data_table => 1, exportable => 0, data_table_config => {bLengthChange => 'false', bFilter => 'false'}, });
  $html .= $table->render || '<h3>No data</h3>';

  $html .= '</div>';

  # repeat navigation div under table
  $html .= '<div>'.$nav_html.'</div>';

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
  if(($field eq 'hgvsc' || $field eq 'hgvsp') && $value =~ /^ENS/) {
    my $action = $field eq 'hgvsc' ? 'Summary' : 'ProteinSummary';

    my @split_value = split(':', $value);

    my $url = $hub->url({
      type    => 'Transcript',
      action  => $action,
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
  elsif($field eq 'spdi') {
    my ($chr, $start, $ref, $alt) = split /\:/, $value;
    $start += 1;
    my $end = $start + length($ref) - 1;
    $start -= 3;
    $end += 3;

    my $url = $hub->url({
      type             => 'Location',
      action           => 'View',
      r                => "$chr:$start-$end",
      contigviewbottom => "variation_feature_variation=normal",
      species          => $species
    });

    $new_value = sprintf('<a class="_ht" title="View in location tab" href="%s">%s</a>', $url, $value);
  }
  elsif($field eq 'hgvsg') {
    my ($chr, $desc) = split /\:/, $value;

    my @coords = $desc =~ /([0-9]+)/g;
    my $pos1 = $coords[0];
    my $pos2 = defined($coords[1]) ? $coords[1] : $pos1;
    my $start = $pos1 <= $pos2 ? $pos1 : $pos2;
    my $end = $pos1 <= $pos2 ? $pos2 : $pos1;
    $start -= 3;
    $end += 3;

    my $url = $hub->url({
      type             => 'Location',
      action           => 'View',
      r                => "$chr:$start-$end",
      contigviewbottom => "variation_feature_variation=normal",
      species          => $species
    });

    $new_value = sprintf('<a class="_ht" title="View in location tab" href="%s">%s</a>', $url, $value);
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
        my $url = $hub->url({
          type   => 'Variation',
          action => 'Explore',
          v      => $item });
        $item_url = qq{<a href="$url">$item</a>};
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
  elsif ($type eq 'vcf_string') {
    foreach my $item (@items_list) {
      push(@items_with_url, $item);
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

## NAVIGATION
#############

sub _navigation {
  my $self = shift;
  my $actual_to = shift;
  my $output_lines = shift;

  my $object = $self->object;
  my $hub = $self->hub;

  # get params
  my %params = map { $_ eq 'update_panel' ? () : ($_ => $hub->param($_)) } $hub->param;
  my $size  = $params{'size'} || 5;
  my $from  = $params{'from'} || 1;
  my $to    = $params{'to'};

  my $orig_size = $size;

  if (defined $to) {
    $size = $to - $from + 1;
  } else {
    $to = $from + $size - 1;
  }

  $actual_to ||= 0;

  print "ACTUAL TO: $actual_to, OUTPUT LINES: $output_lines, FROM: $from, TO: $to, SIZE: $size\n";

  my $this_page   = (($from - 1) / $orig_size) + 1;
  my $page_count  = ceil($output_lines / $orig_size);
  my $showing_all = ($to - $from) == ($output_lines - 1) ? 1 : 0;

  my $html = '';

  # navigation
  unless($showing_all) {
    my $style           = 'style="vertical-align:top; height:16px; width:16px"';
    my $disabled_style  = 'style="vertical-align:top; height:16px; width:16px; opacity: 0.5;"';

    $html .= '<b>Page: </b>';

    # first
    if ($from > 1) {
      $html .= $self->reload_link(qq(<img src="/i/nav-l2.gif" $style title="First page"/>), {
        'from' => 1,
        'to'   => $orig_size,
        'size' => $orig_size,
      });
    } else {
      $html .= '<img src="/i/nav-l2.gif" '.$disabled_style.'/>';
    }

    # prev page
    if ($from > 1) {
      $html .= $self->reload_link(sprintf('<img src="/i/nav-l1.gif" %s title="Previous page"/></a>', $style), {
        'from' => $from - $orig_size,
        'to'   => $to - $orig_size,
        'size' => $orig_size,
      });
    } else {
      $html .= '<img src="/i/nav-l1.gif" '.$disabled_style.'/>';
    }

    # page indicator and count
    $html .= sprintf(
      " %i of %s ",
      $this_page,
      (
        $from == 1 && !($to <= $actual_to && $to < $output_lines) ?
        1 : $page_count
      )
    );

    # next page
    if ($to <= $actual_to && $to < $output_lines) {
      $html .= $self->reload_link(sprintf('<img src="/i/nav-r1.gif" %s title="Next page"/></a>', $style), {
        'from' => $from + $orig_size,
        'to'   => $to + $orig_size,
        'size' => $orig_size,
      });
    } else {
      $html .= '<img src="/i/nav-r1.gif" '.$disabled_style.'/>';
    }

    # last
    if ($to < $output_lines) {
      $html .= $self->reload_link(qq(<img src="/i/nav-r2.gif" $style title="Last page"/></a>), {
        'from' => ($size * int($output_lines / $size)) + 1,
        'to'   => $output_lines,
        'size' => $orig_size,
      });
    } else {
      $html .= '<img src="/i/nav-r2.gif" '.$disabled_style.'/>';
    }

    $html .= '<span style="padding: 0px 10px 0px 10px; color: grey">|</span>';
  }

  # number of entries
  $html .= '<b>Show: </b> ';

  foreach my $opt_size (qw(1 5 10 50)) {
    next if $opt_size > $output_lines;

    if($orig_size eq $opt_size) {
      $html .= sprintf(' <span class="count-highlight">&nbsp;%s&nbsp;</span>', $opt_size);
    }
    else {
      $html .= ' '. $self->reload_link($opt_size, {
        'from' => $from,
        'to'   => $to + ($opt_size - $size),
        'size' => $opt_size,
      });
    }
  }

  # showing all?
  if ($showing_all) {
    $html .= ' <span class="count-highlight">&nbsp;All&nbsp;</span>';
  } else {
    my $warning = '';
    if($output_lines > 500) {
      $warning  = '<img class="_ht" src="/i/16/alert.png" style="vertical-align: top;" title="<span style=\'color: yellow; font-weight: bold;\'>WARNING</span>: table with all data may not load in your browser - use Download links instead">';
    }

    $html .=  ' ' . $self->reload_link("All$warning", {
      'from' => 1,
      'to'   => $output_lines,
      'size' => $output_lines,
   });
  }

  $html .= ' variants';
}

## FILTERS
##########

sub _filters {
  my $self = shift;
  my $headers = shift;
  my $header_titles = shift;

  my $hub = $self->hub;
  my %params = map { $_ eq 'update_panel' ? () : ($_ => $hub->param($_)) } $hub->param;
  my $match = $params{'match'}  || 'and';
  my $html = '';

  $html .= '<div class="toolbox right-margin">';
  $html .= '<div class="toolbox-head"><img src="/i/16/search.png" style="vertical-align:top;"> ';
  $html .= helptip('Filters', "Filter your results to find interesting or significant data. You can apply several filters on any category of data in your results using a range of operators, add multiple filters, and edit active filters");
  $html .= '</div>';
  $html .= '<div style="padding:0px 5px 0px 5px;">';

  my $form_url = $hub->url();
  my $ajax_url = $self->ajax_url(undef, {'update_panel' => 1, '__clear' => 1});

  my $ajax_html .= qq(<form action="#" class="_apply_filter" style="margin: 0;"><input type="hidden" name="ajax_url" value="$ajax_url" />);

  # define operators
  my @operators = (
    {'name' => 'is',  'title' => 'is'},
    {'name' => 'ne',  'title' => 'is not'},
    {'name' => 're',  'title' => 'matches'},
    {'name' => 'lt',  'title' => '<'},
    {'name' => 'gt',  'title' => '>'},
    {'name' => 'lte', 'title' => '<='},
    {'name' => 'gte', 'title' => '>='},
    {'name' => 'in',  'title' => 'in file'},
  );
  my @non_numerical = @operators[0..2];
  my %operators = map {$_->{'name'} => $_->{'title'}} @operators;

  # active filters
  my $active_filters = 0;
  my $filter_number;

  my @filter_divs;
  my @location_divs;

  my @user_files =
    sort { $b->{'timestamp'} <=> $a->{'timestamp'} }
    grep { $_->{'format'} && lc($_->{'format'}) eq 'gene_list' }
    $hub->session->get_record_data({'type' => 'upload'}), $hub->user ? $hub->user->get_records_data({'type' => 'uploads'}) : ();

  my %file_display_name = map { $_->{file} => $_->{name} } @user_files;

  $html .= '<div>';
  foreach my $i (1..$MAX_FILTERS) {
    if ($params{"field$i"}) {
      my $tmp_html;

      $active_filters++;

      # filter display
      $tmp_html .= sprintf('
        <div class="filter filter_edit_%s">
          %s %s %s
          <span style="float:right; vertical-align: top;">
            <a href="#" class="filter_toggle" rel="filter_edit_%s"><img class="_ht" src="/i/16/pencil-whitebg.png" title="Edit filter"></a>
            %s
          </span>
        </div>',
        $i,
        $header_titles->{$params{"field$i"}} || $params{"field$i"},
        $operators{$params{"operator$i"}},
        $params{"operator$i"} eq 'in' ? $file_display_name{$params{"value_dd$i"}} : ($params{"value$i"} ne "" ? $params{"value$i"} : 'defined'),
        $i,
        $self->reload_link('<img class="_ht" src="/i/close.png" title="Remove filter" style="height:16px; width:16px">', {
          "field$i"       => undef,
          "operator$i"    => undef,
          "value$i"       => undef,
          "value_dd$i"    => undef,
          'update_panel'  => undef
        })
      );

      # edit filter
      $tmp_html .= qq(<div class="filter_edit_$i" style="display:none;">);
      $tmp_html .= $ajax_html;

      # field
      $tmp_html .= qq('<select class="autocomplete" name="field$i">);
      $tmp_html .= sprintf(
        '<option value="%s" %s>%s</option>',
        $_,
        $_ eq $params{"field$i"} ? 'selected="selected"' : '',
        $header_titles->{$_} || $_
      ) for @$headers;
      $tmp_html .= '</select>';

      # operator
      $tmp_html .= qq(<select name="operator$i" class="_operator_dd">);
      $tmp_html .= sprintf(
        '<option value="%s" %s>%s</option>',
        $_->{'name'},
        ($_->{'name'} eq $params{"operator$i"} ? 'selected="selected"' : ''),
        $_->{'title'}
      ) for @operators;
      $tmp_html .= '</select>';

      # value and submit
      $tmp_html .= sprintf(
        qq(<input class="autocomplete _value_switcher %s" type="text" placeholder="defined" name="value$i" value="%s" />),
        $params{"operator$i"} eq 'in' ? 'hidden' : '',
        $params{"value$i"}
      );

      # value (dropdown file selector)
      $tmp_html .= sprintf(
        '<span class="_value_switcher %s">',
        $params{"operator$i"} eq 'in' ? '' : 'hidden'
      );
      if(scalar @user_files) {
        $tmp_html .= '<select name="value_dd'.$i.'">';
        $tmp_html .= sprintf(
          '<option value="%s" %s>%s</option>',
          $_->{file},
          $_->{file} eq $params{"value_dd$i"} ? 'selected="selected"' : '',
          $_->{name}
        ) for @user_files;
        $tmp_html .= '</select>';
      }
      my $url = $hub->url({
        type   => 'UserData',
        action => 'SelectFile',
        # format => 'GENE_LIST'
      });
      $tmp_html .= '<span class="small"> <a href="'.$url.'" class="modal_link data" rel="modal_user_data">Upload file</a> </span>';
      $tmp_html .= '</span>';

      # update/submit
      $tmp_html .= '<input value="Update" class="fbutton" type="submit" />';

      # add hidden fields
      $tmp_html .= sprintf('<input type="hidden" name="%s" value="%s">', $_, $params{$_}) for grep {!/[a-z]$i$/i} keys %params;
      $tmp_html .= '</form>';
      $tmp_html .= qq(<div style="padding-left: 2px;"><a href="#" class="small filter_toggle" style="color:white;" rel="filter_edit_$i">Cancel</a></div>);
      $tmp_html .= '</div>';

      if($params{"field$i"} =~ /^Location/) {
        push @location_divs, $tmp_html;
      } else {
        push @filter_divs, $tmp_html;
      }
    } else {
      $filter_number ||= $i;
    }
  }

  foreach my $div (@location_divs) {
    $html .= qq(<div class="location-filter-box filter-box">$div</div>);
  }
  # $html .= '<hr style="margin:2px"/>' if scalar @location_divs && scalar @filter_divs;

  foreach my $div (@filter_divs) {
    $html .= qq(<div class="filter-box">$div</div>);
  }

  $html .= '</div>';

  if ($active_filters > 1) {
    my %logic = (
      'or'  => 'any',
      'and' => 'all',
    );

    # clear
    $html .= '<div style="float:left;">'.$ajax_html;
    $html .= sprintf('<input type="hidden" name="%s" value="%s">', $_, $params{$_}) for grep {!/(field|operator|value|match)/} keys %params;
    $html .= '<input value="Clear filters" class="fbutton" type="submit">';
    $html .= '</form></div>';

    if(scalar @filter_divs > 1) {
      $html .= '<div style="float:right;">'.$ajax_html;
      $html .= 'Match <select name="match"">';
      $html .= sprintf('<option value="%s" %s>%s</option>', $_, ($_ eq $match ? 'selected="selected"' : ''), $logic{$_}) for sort keys %logic;
      $html .= '</select> of the above rules ';
      $html .= sprintf('<input type="hidden" name="%s" value="%s">', $_, $params{$_}) for grep {!/match/} keys %params;
      $html .= '<input value="Update" class="fbutton" type="submit">';
      $html .= '</form></div>';
    }
  }

  # start form
  #$html .= sprintf('<div style="display:inline-block;"><form action="%s" method="get">', $form_url);
  $html .= '<div style="clear: left;">';

  # $html .= '<hr style="margin:2px"/>' if $active_filters;
  $html .= $ajax_html;

  # field
  $html .= '<select class="autocomplete right-margin" name="field'.$filter_number.'">';
  $html .= sprintf('<option value="%s">%s</option>', $_, $header_titles->{$_} || $_) for @$headers;
  $html .= '</select>';

  # operator
  $html .= '<select class="_operator_dd right-margin" name="operator'.$filter_number.'">';
  $html .= sprintf('<option value="%s" %s>%s</option>', $_->{name}, ($_->{name} eq 'is' ? 'selected="selected"' : ''), $_->{title}) for @operators;
  $html .= '</select>';

  # value (text box)
  $html .= '<input class="autocomplete _value_switcher right-margin" type="text" placeholder="defined" name="value'.$filter_number.'">';

  # value (dropdown file selector)
  $html .= '<span class="_value_switcher hidden">';
  if(scalar @user_files) {
    $html .= '<select name="value_dd'.$filter_number.'">';
    $html .= sprintf('<option value="%s">%s</option>', $_->{file}, $_->{name}) for @user_files;
    $html .= '</select>';
  }
  my $url = $hub->url({
    type   => 'UserData',
    action => 'SelectFile',
    # format => 'GENE_LIST'
  });
  $html .= '<span class="small"> <a href="'.$url.'" class="modal_link data" rel="modal_user_data">Upload file</a> </span>';
  $html .= '</span>';

  # submit
  $html .= '<input value="Add" class="fbutton" type="submit">';

  # add hidden fields
  $html .= sprintf('<input type="hidden" name="%s" value="%s">', $_, $params{$_}) for keys %params;
  $html .= '</form></div>';

  $html .= '</div></div>';

  return [$html, $active_filters];
}

sub reload_link {
  my ($self, $html, $url_params) = @_;

  return sprintf('<a href="%s" class="_reload"><input type="hidden" value="%s" />%s</a>',
    $self->hub->url({%$url_params, 'update_panel' => undef}, undef, 1),
    $self->ajax_url(undef, {%$url_params, 'update_panel' => 1}, undef, 1),
    $html
  );
}

sub zmenu_link {
  my ($self, $url, $zmenu_url, $html) = @_;

  return sprintf('<a class="_zmenu" href="%s">%s</a><a class="hidden _zmenu_link" href="%s"></a>', $url, $html, $zmenu_url);
}

1;

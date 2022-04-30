#
# Copyright (c) 2014, 2015 by Oracle Corporation. All Rights Reserved.
#
#
package APF::PBuild::StackPatchBundle;

use Archive::Zip;
use ARU::Const;
use APF::Zip;
use Debug;
use File::Basename;
use ISD::Text;
use Template;
use APF::PBuild::Util;
use APF::PBuild::Base;
use APF::PBuild::GenerateReadme;
use JSON qw( decode_json );
use Data::Dumper;
use List::MoreUtils qw(uniq);
use APF::PBuild::PostProcess;
use vars qw(@ISA);
use strict;
use DoSystemCmd;
@ISA = qw(APF::PBuild::Base);
use ConfigLoader "PB::Config" => "$ENV{ISD_HOME}/conf/pbuild.pl";


#
# Module for building Stack Patch Bundle
#

sub new {
    my ($class, $options) = @_;

    my $request_id = $options->{request_id};
    my $work_area = PB::Config::apf_base_work . "/$request_id";

    my $self = bless (APF::PBuild::Base->new(
        work_area  => $work_area,
        request_id => $request_id,
        log_fh => $options->{log_fh},),
        $class);
    #
    # Save all options
    #
    foreach my $key (keys %$options) {
        $self->{$key} = $options->{$key}
            if (!(defined($options->{$key}) && $options->{$key} ne ''));
    }
    $self->{apf_req_url} = APF::Config::http_protocol . APF::Config::url_host_port .
        "/ARU/BuildStatus/process_form?rid=".
        $self->{request_id};

    my $aru_obj = new ARU::BugfixRequest($options->{aru_no});
    $aru_obj->get_details();

    $self->{aru_no} = $options->{aru_no};
    $self->{aru_obj} = $aru_obj;
    $self->{pse} = $options->{bug};
    $self->{base_work} = PB::Config::apf_base_work;
    return $self;
}



sub stack_patch_build {

    my ($self, $preprocess) = @_;
    my $log_fh = $self->{log_fh};

    $log_fh->print("self dumper " .Dumper($self)."\n");
    my $bugfix_request_id = $self->{aru_no};
    my $pse = $self->{pse};
    my $aru_obj;
    $self->{bpr_label} = $self->{label};
    my $is_readme_avail;

    if ($self->{aru_obj}->{aru}) {
        $aru_obj = $preprocess->{aru_obj};
    }
    else {
        $aru_obj = new ARU::BugfixRequest($bugfix_request_id);
        $aru_obj->get_details();
        $self->{aru_obj} = $preprocess->{aru_obj} = $aru_obj;
    }


    ARUDB::exec_sp('apf_queue.update_aru', $bugfix_request_id,
        ISD::Const::st_apf_preproc);

    my ($base_bug, $utility_ver, $platform_id, $prod_id,
        $category, $sub_component) =
        $self->get_bug_details_from_bugdb($pse);

    $self->{base_bug} = $base_bug;
    $self->{blr} = $pse;
    $self->{utility_version} = $utility_ver;
    $self->{category} = $category;
    $self->{bugdb_prod_id} = $prod_id;
    $self->{bug_utility_version} = $utility_ver;
    my $work_area = $self->{work_area};

    $self->get_pse_details($self->{pse}, 0);
    #
    # store details in ABB table
    #
    #
    # First delete the backports for this aru and insert new set
    # of backports.
    #
    ARUDB::exec_sp("aru_upload.delete_aru_pse_backport",
        $bugfix_request_id);

    ARUDB::exec_sp("aru_upload.create_aru_backports",
        $bugfix_request_id,
        $self->{pse},
        ARU::Const::upload_fixes_bug_default,
        ISD::Const::st_pse);

    #
    #  Allow the patches created by ST APF to override by Patch Upload
    #
    ARUDB::exec_sp("aru_bugfix_attribute.set_bugfix_attribute",
        $aru_obj->{bugfix_id},
        ARU::Const::aru_application_id,
        ARU::Const::application_upload);

    #
    # Generate Stack Patch
    #
    $self->generate_stack_bundle_patch();
    $self->{system}->do_chdir($work_area);



    #
    # Generate README.html
    #
    $log_fh->print_header("Generate Readme");
    my $repo = $self->{spb}->{repo_name};
    $log_fh->print("Aru dir is : $self->{aru_dir}\n");
    if($self->{spb}->{cpm_product_name} eq 'IDM') {
        $is_readme_avail = $self->generate_readme("$self->{aru_dir}/README.html");
    }
    else
    {
        my $vars;
        my $gen_readme = APF::PBuild::GenerateReadme->new
            ({system => $self->{system},
                log_fh => $self->{log_fh},
                bugfix_req_id   => $self->{aru_obj}->{aru},
                aru_obj => $self->{aru_obj},
                request_id => $self->{request_id},
                pse => $self->{pse},
                product_id => $self->{aru_obj}->{product_id},
                label  =>
                    $self->{bpr_label},
                describe => $self->{aru_obj}->{describe}});

        $is_readme_avail =  $gen_readme->generate_readme('',
            $self->{aru_obj}->{bug},
            $vars,
            "$self->{aru_dir}/README.html",
            $self);


    }

    my ($disable_readme_txt_prods) =
        ARUDB::exec_sf("aru_parameter.get_parameter_value",
            'DISABLE_README_TEXT_SPB_BUNDLE');
    my @txt_prods = split(',', $disable_readme_txt_prods);
    my $text_readme = 1;
    if (grep(/$self->{spb}->{cpm_product_name}/, @txt_prods)) {
        $text_readme = 0;
        $log_fh->print("\nCreating dummy Readme.txt \n");
        $self->{system}->do_cmd_ignore_error
            ("echo 'Refer to README.html' > $self->{aru_dir}/README.txt");

    }

    if ( ($is_readme_avail == 0) || (!-e "$self->{aru_dir}/README.html")) {
        $log_fh->print("\nAutomation generated Readme not available \n");
        my $readme_msg="Readme generation failed. Invalid Readme Generated \n"
            .$self->{spb}->{readme_failure};
        ARUDB::exec_sp('bugdb.async_create_bug_text',
            $pse, $readme_msg);
        $self->{system}->do_cmd_ignore_error
            ("echo 'ERROR: Readme generation failed' > $self->{aru_dir}/README.html");
        if($text_readme == 1)
        {
            $self->{system}->do_cmd_ignore_error
                ("echo 'ERROR: Readme generation failed' > $self->{aru_dir}/README.txt");
        }
    }



    $self->{system}->do_cmd_ignore_error
        ("cp $self->{aru_dir}/README.html " .
            " $self->{aru_dir}/$repo");
    $self->{system}->do_cmd_ignore_error
        ("cp $self->{aru_dir}/README.txt " .
            " $self->{aru_dir}/$repo");


    #
    # Package the patch
    #
    $log_fh->print_header("Package the Patch");
    $self->package_spb();


    #
    # push patch to repository
    #
    $log_fh->print_header("Enqueued to Repository Loader");
    my $post_proc = APF::PBuild::PostProcess->new($aru_obj,
        $work_area,
        $log_fh,
        $aru_obj->{aru});

    $post_proc->{aru_no} = $post_proc->{bugfix_request_id} = $aru_obj->{aru};
    $post_proc->{pse} = $self->{pse};
    $post_proc->{spb_html_readme} = 1;
    $post_proc->copy_patch_to_transient_dir();
    $post_proc->push_to_patch_repository();

    #
    # Store Series Attributes
    # 

    $self->store_series_attributes($self->{spb}->{series_id});

    #
    # update the bug
    #
    my $aru = $aru_obj->{aru};
    my $release = $aru_obj->{release};
    my $version = APF::PBuild::Util::get_version($release);
    my $aru_info = "$version ARU $aru";

    my $upd_text = "$aru_info packaged for $aru_obj->{platform} using the following patches:\n";
    $upd_text .= $self->{msg};
    $upd_text .= "\n";
    $log_fh->print("Updating base_bug $base_bug with $upd_text\n");

    eval
    {
        ARUDB::exec_sp('bugdb.async_create_bug_text',
            $aru_obj->{bug}, $upd_text);

        ARUDB::exec_sp('bugdb.async_create_bug_text',
            $pse, $upd_text);
    };
    $log_fh->print("Unable to update base bug: $@\n") if ($@);

    #
    #send email notification
    #
    my $url_host_port = APF::Config::url_host_port;
    #
    # strip the port no for better formatting,
    # see bug#9534035 for details.
    #
    my $port;
    ($url_host_port, $port) = split(':', $url_host_port)
        if (ConfigLoader::runtime("production"));

    my $status_link = APF::Config::http_protocol . $url_host_port .
        "/ARU/BuildStatus/process_form?rid=" . $self->{request_id};
    my $request_id_link = "<a href=\"$status_link\">$self->{request_id}</a>";
    #
    # send email_subject notification
    #
    my $options = {
        'log_fh'       => $log_fh,
        'product_id'   => $aru_obj->{product_id},
        'release_id'   => $aru_obj->{release_id},
        'version'      =>
            $aru_obj->{release} || $aru_obj->{release_long_name},
        'product_name' => $aru_obj->{product_name},
        'subject'      =>
            $self->{spb}->{cpm_product_name}." Stack Patch Bundle Packaging completed for $aru_obj->{bug} on $aru_obj->{platform_id}",
        'comments'     =>
            "is patch packaged" .
                "Awaiting for the DTE install tests to get kicked off.",
        'platform'     => $aru_obj->{platform},
        'bug'          => $aru_obj->{bug},
        'request_log'  => $request_id_link
    };

    APF::PBuild::Util::send_bp_email_alerts($options);
}

sub store_series_attributes {

    my ($self,$series_id)= @_;
    
    my $bugfix_id = $self->{aru_obj}->{bugfix_id};
    my %series_attr_types = ARU::Const::spb_series_attrs;
    $self->{log_fh}->print("Dumping the store series attributes bugfix_id $bugfix_id");
    my $results = ARUDB::query('GET_SERIES_ATTRIBUTES',$series_id,"");
    my (@other_attrs,@spb_run_attrs);
    push(@spb_run_attrs,"label:$self->{label}");
    push(@spb_run_attrs,"psu:$self->{pse}");
    push(@spb_run_attrs,"aru:$self->{aru_no}");
    ARUDB::exec_sp('aru_bugfix_attribute.set_bug_details_attribute',
                    $bugfix_id, $series_attr_types{SPB_RUN_ATTRS}, join(",", @spb_run_attrs));  
    $self->{log_fh}->print("==>Saving attribute: type:  $series_attr_types{SPB_RUN_ATTRS} \n".join(",", @spb_run_attrs));
    foreach my $row (@$results)
    {
        my ($attribute_value, $attribute_name) = @$row;
        if(exists($series_attr_types{$attribute_name})){
            my $type   = $series_attr_types{$attribute_name};
            my $value  = $self->{lc $attribute_name};
            $value ||= $attribute_value;
            ARUDB::exec_sp('aru_bugfix_attribute.set_bug_details_attribute',
            $bugfix_id, $type, $value); 
        }else{
            push(@other_attrs,"$attribute_name:$attribute_value");
        }
    }     
    ARUDB::exec_sp('aru_bugfix_attribute.set_bug_details_attribute',
                    $bugfix_id, $series_attr_types{SPB_OTHER_SERIES_ATTRS}, join(",", @other_attrs));  
    $self->{log_fh}->print("==>Saving attribute: type:  $series_attr_types{SPB_OTHER_SERIES_ATTRS} \n".join(",", @other_attrs));
                     
}

sub gen_readme_comp_section {
    my ($self, $series_id, $type) = @_;
    my $log_fh = $self->{log_fh};
    my @all_patches = @{$self->{spb}->{patches}};
    #
    # Read the template file
    #
    $log_fh->print("Generating bug list section for $type patches\n");

    my $comp_bug_section = '<table border="1" cellpadding="4" >
    <thead> <tr>
    <th style="text-align:center" >' . ($type eq 'config' ? 'Config ' : '') . 'Patches</th>
    <th style="text-align:center" >Patch Number</th>
    <th style="text-align:center" colspan="4" >Applicability</th>
    </tr> </thead>
    <tbody> %table_body% </tbody> </table>';
    my $table_body = "";

    $log_fh->print("Reading series attributes to get components name for IDM products install homes\n");
    my ($OAM_PRODUCTS, $OID_PRODUCTS, $OIG_PRODUCTS, $OUD_PRODUCTS);
    $OAM_PRODUCTS =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_OAM_HOME_COMPONENTS');
    $log_fh->print("Components for OAM install homes : $OAM_PRODUCTS\n");
    $OIG_PRODUCTS =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_OIG_HOME_COMPONENTS');
    $log_fh->print("Components for OIG/OIM install homes : $OIG_PRODUCTS\n");
    $OUD_PRODUCTS =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_OUD_HOME_COMPONENTS');
    $log_fh->print("Components for OUD install homes : $OUD_PRODUCTS\n");
    $OID_PRODUCTS =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_OID_HOME_COMPONENTS');
    $log_fh->print("Components for OID install homes : $OID_PRODUCTS\n");

    if(($OAM_PRODUCTS eq "") || ($OIG_PRODUCTS eq "")
        || ($OUD_PRODUCTS eq "") || ($OID_PRODUCTS eq "")) {
        $self->{spb}->{readme_failure} =
            "SPB_*_HOME_COMPONENTS value not set for one or more IDM products in CPM Series Attributes";
        $log_fh->print("Value not defined for one or more SPB_*_HOME_COMPONENTS in Series Attributes\n");
        return;
    }

    #
    # Fetch series parameter to get component applicability
    #

    my @patches = grep {$_->{type} eq $type} @all_patches;

    #
    # Construct table body
    #
    foreach my $patch (@{patches}) {
        $table_body .= "<tr>";
        #
        # Remove html special characters from bug abstract
        #
        $table_body .= "<td> ".ISD::Text::escape_html($patch->{bug_abstract})." </td>";
        $table_body .= "<td> ".($patch->{tracking_bug})." </td>";
        #
        # OAM,OIG,OUD,OID
        #
        $table_body .= "<td align='center'>" . (($OAM_PRODUCTS =~ /$patch->{comp_name}/i) ? "OAM" : "-") . "</td>";
        $table_body .= "<td align='center'>" . (($OIG_PRODUCTS =~ /$patch->{comp_name}/i) ? "OIG" : "-") . "</td>";
        $table_body .= "<td align='center'>" . (($OUD_PRODUCTS =~ /$patch->{comp_name}/i) ? "OUD" : "-") . "</td>";
        $table_body .= "<td align='center'>" . (($OID_PRODUCTS =~ /$patch->{comp_name}/i) ? "OID" : "-") . "</td>";
        $table_body .= "</tr>";
        $table_body .= "\n";
    }

    $comp_bug_section =~ s/%table_body%/$table_body/;
    $log_fh->print(uc($type) . " Component Section : $comp_bug_section\n");
    return $comp_bug_section;
}

sub fetch_readme_template {

    my ($self, $series_id) = @_;
    my $log_fh = $self->{log_fh};
    my $aru_obj = $self->{aru_obj};

    #
    # check if there is any readme template registered for a given series
    #
    $self->{log_fh}->print("GET_README_TEMPLATE FOR : $aru_obj->{product_id}-$aru_obj->{release_id}-$series_id-$aru_obj->{platform_id}\n");

    my ($readme_tmpl) = ARUDB::single_row_query
        ("GET_README_TEMPLATE_ID_SERIES",
            $series_id,
            $aru_obj->{platform_id});

    unless ($readme_tmpl) {
        $log_fh->print("There is no readme template defined for series $series_id\n");
        return;
    }
    my $dbh = ARUDB::get_connection();
    my $sql = qq/select template from automation_readme_templates where tmpl_id=?/;

    my $sth = $dbh->prepare(
        $sql,
        { ora_auto_lob => 0 }
    );

    $sth->execute($readme_tmpl);
    my ($char_locator) = $sth->fetchrow_array();
    my $chunk_size = 1034; # Arbitrary chunk size, for example
    my $offset = 1;        # Offsets start at 1, not 0

    my $static_text;

    while (my $buffer = $dbh->ora_lob_read($char_locator,
        $offset,
        $chunk_size)) {
        $static_text .= $buffer;
        $offset += $chunk_size;
    }

    $log_fh->print("Static Readme Template for $series_id " .
        "is:\n $static_text\n\n");

    $self->{log_fh}->print("\n+--------END OF README TEMPLATE CONTENT--------+\n\n");

    return $static_text;

}

sub generate_readme {
    my ($self, $output_file) = @_;
    my $log_fh = $self->{log_fh};
    my $aru_obj = $self->{aru_obj};
    my $readme_tmpl;
    my $tracking_bug = $self->{aru_obj}->{bug};
    my $year = 1900 + (localtime)[5];

    my ($series_name, $release_name);
    ARUDB::exec_sp
        ('aru_cumulative_request.get_tracking_bug_details',
            $tracking_bug, \$series_name, \$release_name);

    $log_fh->print("Stack Patch series name is:$series_name:\n");
    $log_fh->print("Stack Patch release name is:$release_name:\n");

    my ($series_id) = ARUDB::exec_sf('aru_cumulative_request.get_series_id',
        $series_name);

    #
    # Fetch readme template, if no template is defined. return.
    #
    return 0 # 0 implies that readme generation is unsuccessful.
        unless ($readme_tmpl = $self->fetch_readme_template($series_id));

    my $readme_hash;
    if($self->{spb}->{cpm_product_name} eq 'IDM') {
        my $spb_binary_patches = $self->gen_readme_comp_section($series_id, 'binary');
        my $spb_config_patches = $self->gen_readme_comp_section($series_id, 'config');
        $readme_hash->{'spb_binary_patches'} = $spb_binary_patches;
        $readme_hash->{'spb_config_patches'} = $spb_config_patches;
    }

    $readme_hash->{'aruplatformname'} = $self->{aru_obj}->{platform};
    $readme_hash->{'relversion'} = $self->{spb}->{version};
    $readme_hash->{'spb_opatch_zip'} = $self->{spb}->{spb_opatch_zip};
    $readme_hash->{'year'} = $year;
    $readme_hash->{'productname'} = $self->{aru_obj}->{product_name};
    $readme_hash->{'trackingbug'} = $self->{aru_obj}->{bug};


    $log_fh->print("Readme hash : " . Dumper($readme_hash) . "\n");
    #
    # Replace variable tags in readme
    # As there is limited variable data, we are replacing the tags in readme individually in the
    # same module
    #
    while ($readme_tmpl =~ /(%[^%]+?(ARU_\w+).*?%)/sg) {
        my ($tag, $txt) = ($1, $2);
        $txt =~ s/.*?(ARU.*?)\W/\1/;
        my $sub = $txt;
        $sub =~ s/ARU\_//;
        $log_fh->print("Substituting $tag ($txt) with " . lc($sub) . "->" . $readme_hash->{lc($sub)} . "\n");
        if ((defined($readme_hash->{lc($sub)}) && $readme_hash->{lc($sub)} ne "")) {
            $readme_tmpl =~ s/$tag/$readme_hash->{lc($sub)}/g
        }
        else {
            return 0; # 0 implies that readme generation is unsuccessful.
        }

    }
    my $readme_fh = new FileHandle(">$output_file");
    return 0 unless ($readme_fh);

    $readme_fh->print($readme_tmpl);
    $readme_fh->close();

    $log_fh->print("\n+-------- README CONTENT -------+\n");
    $log_fh->print($readme_tmpl);
    $log_fh->print("\n+-------- END OF CONTENT -------+\n");
    $log_fh->print("Readme generation successful\n");
    return 1;

}


sub generate_stack_bundle_patch {

    my ($self) = @_;
    my $log_fh = $self->{log_fh};
    my $aru_obj = $self->{aru_obj};

    $log_fh->print_header("Fetch Component Patch Details");

    my ($series_name, $release_name);
    ARUDB::exec_sp('aru_cumulative_request.get_tracking_bug_details',
        $aru_obj->{bug}, \$series_name, \$release_name);
    my ($series_id) = ARUDB::exec_sf('aru_cumulative_request.get_series_id',
        $series_name);
    $log_fh->print("Release name for bug $aru_obj->{bug} is $release_name\n");
    $self->{series_name} = $series_name;

    my ($patch_desc_util, $utility_ver) = ($release_name =~ /(.*) (.*)/);
    $log_fh->print("Patch description value is $patch_desc_util" .
        " & Utility Version: $utility_ver\n");


    #
    # Set SPB Repository Name
    #
    my ($label_date) = ($self->{label} =~ /.*_(.*)\..*$/);
    $log_fh->print("Label is " . $self->{label} . "\n");
    $log_fh->print("Label date is $label_date\n");
    #$dated_id =~ m/(\d{1,6})\.?(.*)/;
    my ($utility_version) = ARUDB::single_row_query('GET_UTILITY_VERSION',
        $self->{pse});
    my $spb_version = $utility_version;
    $spb_version =~ s/\.0$/\.$label_date/;

    #
    # Disable existing comp record for the SPB ARU
    #
    ARUDB::exec_sp("aru.apf_spb_patch_detail.delete_spb_aru_detail",
        $self->{aru_obj}->{aru},
        ARU::Const::apf_userid );


    #
    # Read series product family name to add prefix in the repository
    #
    my ($cpm_product_name) = ARUDB::single_row_query("GET_CPM_PROD_NAME",
            $series_id);
    $self->{spb}->{cpm_product_name} = $cpm_product_name;
    $self->{spb}->{version} = $spb_version;
    $self->{localtime} = localtime();
    $self->{spb}->{series_id} = $series_id;
    $self->{spb}->{tracking_bug} = $aru_obj->{bug};
    $self->{spb}->{repo_name} = $cpm_product_name ."_SPB_" . $spb_version;
    $log_fh->print("Patch top directory : $self->{spb}->{repo_name}\n");

    #
    # shift to work are
    #
    $self->{system}->do_chdir($self->{aru_dir});


    #
    # Fetch the component patches details
    #

    $log_fh->print("Tracking bug is : $self->{aru_obj}->{bug}\n");
    $self->fetch_subpatch_details($self->{aru_obj}->{bug});

    #
    # Download component patches
    #
    $log_fh->print_header("Download Component Patches");
    $self->download_component_patches();
    $log_fh->print("Download complete\n");

    $self->{system}->do_chdir($self->{aru_dir});

    #
    # Generate SPB Tracking Patch 
    #
    eval{
        my ($tracker_patch_mode) = ARUDB::exec_sf('aru_parameter.get_parameter_value','SPB_TRACKER_PATCH_MODE');
        # my $info_patch = $self->generate_info_patch() if ($tracker_patch_mode eq 'Y');
    };

    #
    #Create spbat-bundle.properties under repository
    #

    my $spbat_properties_file = "$self->{spb}->{repo_name}/spbat-bundle.properties";
    $self->{system}->do_mkdir($self->{spb}->{repo_name}, 0755);
    my $spbat_properties_fh = new FileHandle("> $spbat_properties_file");
    $log_fh->print("Adding the content to spbat-bundle.properties file \n");
    $self->set_spbat_properties($spbat_properties_fh,$utility_version);
    $log_fh->print("Added the content to spbat-bundle.properties file \n");
    $spbat_properties_fh->close();
    $self->{system}->do_chmod(0755, "$spbat_properties_file");


}

sub set_spbat_properties {
    my ($self, $spbat_properties_fh,$utility_version) = @_;
    my $cpm_product_name = $self->{spb}->{cpm_product_name};
    my $spb_version = $self->{spb}->{version};
    my $series_id = $self->{spb}->{series_id};

    if($cpm_product_name =~/^(WLS|IDM)$/)
    {
        $spbat_properties_fh->print("SUPPORTED_FMW_RELEASE=$utility_version\n");
        $spbat_properties_fh->print($cpm_product_name . "_SPB_VERSION=$spb_version\n");
    }

    if($cpm_product_name ne 'IDM')
    {
        $spbat_properties_fh->print("SPB_VERSION=$spb_version\n");
        my $version = $utility_version;
        if($cpm_product_name eq 'OAS')
        {
            my $util_version = '';
            eval {
                $util_version = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                    'OAS_SPB_RELEASE_VERSION');
            };
            if( $util_version =~ /($utility_version:([^,]*))/ )
            {
                $version = $2;
            }
        }
        $spbat_properties_fh->print("SPB_SUPPORTED_RELEASE=$version\n");
    }
    # Add attributes from series starting with SPBAT_{attribute_name} to  spbat_properties file, see 33860189 
    eval{
        my $results = ARUDB::query('GET_SERIES_REQ_ATTRIBUTE',$series_id,'^SPBAT_','Y');
        foreach my $row (@$results)
        {
            my ($attribute_value, $attribute_name) = @$row;
            $attribute_name = (split(/SPBAT_/, $attribute_name))[1];
            $spbat_properties_fh->print("$attribute_name=$attribute_value\n");
        }
    };
}

sub package_spb {

    my ($self) = @_;
    my $log_fh = $self->{log_fh};
    $self->{system}->do_chdir($self->{aru_dir});

    #
    # Remove any existing zip and bug folder
    #
    $self->{system}->do_cmd_ignore_error
        ("rm -rf $self->{aru_obj}->{bug}" . ".zip");

    $self->{system}->do_cmd_ignore_error
        ("rm -rf $self->{aru_obj}->{bug}");

    #
    # Zip the patch content
    #
    my $cmd = "/usr/bin/zip -r $self->{aru_obj}->{bug}" . ".zip $self->{spb}->{repo_name}";
    $self->exec_retry_command
        (do_cmd_obj => $self->{system},
            method  => 'do_cmd_ignore_error',
            args    => [ $cmd, (keep_output => 'YES',
                timeout                     => PB::Config::ssh_timeout) ]);


    $cmd="chmod 0755 ".$self->{aru_obj}->{bug}.".zip";
    $self->{system}->do_cmd_ignore_error($cmd);
    #
    # Rename the repository to bug# folder for README logic
    #
    $cmd = "mv $self->{spb}->{repo_name} $self->{aru_obj}->{bug}";
    $self->{system}->do_cmd_ignore_error($cmd);

    $self->{system}->do_cmd_ignore_error
        ("cp $self->{aru_dir}/README.html " .
            " $self->{aru_dir}/$self->{aru_obj}->{bug}");

    $self->{system}->do_cmd_ignore_error
        ("cp $self->{aru_dir}/README.txt " .
            " $self->{aru_dir}/$self->{aru_obj}->{bug}");

    $log_fh->print("Patch packaged successfully\n");

}

#
# api to fetch the latest subpatches associated with the system patch
# download the patches into the workarea
# populate HAS/WLM/TOMCAT/DBWLM/DBPSU details
# update the tracking bug
#
sub fetch_subpatch_details {
    my ($self, $tracking_bug) = @_;

    my $log_fh = $self->{log_fh};
    my $system = $self->{system};
    my $work_area = $self->{work_area};

    $self->get_component_patches($tracking_bug);
    $system->do_chdir($work_area);

    #
    # insert component patches in database
    #

}


sub get_config_patches_details {
    my ($self, $series_id) = @_;
    my $log_fh = $self->{log_fh};

    #Config patch location
    my ($config_patches_location) =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_CONFIG_PATCHES_LOCATION');

    $config_patches_location ||= $self->{spb_config_patches_aru_loc};    
    ISD::Text::strip_whitespace(\$config_patches_location);
    $log_fh->print("Config patch location is : $config_patches_location\n\n");
    $self->{spb}->{config_patches_location} = $config_patches_location;

    #config arus
    my ($config_patches_aru) =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_CONFIG_PATCHES_ARU');
    $log_fh->print("Config patches provided in series parameter : $config_patches_aru\n\n");

    $config_patches_aru = $self->get_unique_values($config_patches_aru,$self->{spb_config_patches_aru});
    $self->{spb_config_patches_aru} = $config_patches_aru;
    $log_fh->print("Config patches provided in series parameter with SPB's Included: $config_patches_aru\n\n");

    $self->process_comp_aru_parameters($config_patches_aru, $config_patches_location, 'config');
}

sub get_tool_patches_details {
    my ($self, $series_id) = @_;
    my $log_fh = $self->{log_fh};

    #
    # Tools patch location
    #
    my ($tool_patches_location) =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_TOOL_PATCHES_LOCATION');

    $tool_patches_location ||= $self->{spb_tool_patches_aru_loc};                    
    ISD::Text::strip_whitespace(\$tool_patches_location);
    $log_fh->print("Tool patch location is : $tool_patches_location\n\n");
    $self->{spb}->{tool_patches_location} = $tool_patches_location;

    # Tool patch arus
    my ($tool_patches_aru) =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_TOOL_PATCHES_ARU');

    $log_fh->print("Tool patches provided in series parameter : $tool_patches_aru\n\n");

    $tool_patches_aru = $self->get_unique_values($tool_patches_aru,$self->{spb_tool_patches_aru});
    $self->{spb_tool_patches_aru} = $tool_patches_aru;
    $log_fh->print("Tool patches provided in series parameter with SPB's included : $tool_patches_aru\n\n");

    #
    # If no tool patch is available then die.
    #
    die("SPB_TOOL_PATCHES_ARU not defined in series configuration")
        unless ($tool_patches_aru);

    $self->process_comp_aru_parameters($tool_patches_aru, $tool_patches_location, 'tool');

}

sub get_binary_patches_details {
    my ($self, $series_id) = @_;
    my $log_fh = $self->{log_fh};
    
    #Binary patch location
    my ($binary_patches_location) =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_BINARY_PATCHES_LOCATION');

    $binary_patches_location ||= $self->{spb_binary_patches_aru_loc};            
    ISD::Text::strip_whitespace(\$binary_patches_location);
    $log_fh->print("Binary patch location is : $binary_patches_location\n\n");
    $self->{spb}->{binary_patches_location} = $binary_patches_location;

    #
    # Binary patch arus
    #
    my ($binary_patches_aru) =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_BINARY_PATCHES_ARU');
    $log_fh->print("Binary patches provided in series parameter : $binary_patches_aru\n\n");

    $binary_patches_aru = $self->get_unique_values($binary_patches_aru,$self->{spb_binary_patches_aru});
    $self->{spb_binary_patches_aru} = $binary_patches_aru;
    $log_fh->print("Binary patches provided in series parameter with SPB's included: $binary_patches_aru\n\n");

    $self->process_comp_aru_parameters($binary_patches_aru, $binary_patches_location, 'binary');

    #
    # Component series ARUs
    #
    my ($comp_series_names) =
        ARUDB::exec_sf
            ('aru_cumulative_request.get_series_attribute_value',
                $series_id, 'SPB_COMPONENT_CPM_SERIES');
    $log_fh->print("SPB_COMPONENT_CPM_SERIES attribute : $comp_series_names\n");

    #my ($series_patch_arus)=$self->get_latest_component_patch($comp_series_names);
    $self->process_comp_series_parameters($comp_series_names, $binary_patches_location, 'binary');

}

sub get_unique_values {
    my ($self,@arr) = @_;
    my $complete_val = lc join (",",@arr);
    @arr = split(',',$complete_val);
    @arr = uniq(@arr);
    return join (",",@arr);
}
sub get_latest_comp_releases {
    my ($self,$series_id) = @_;
    my ($release_id, $release_name, $tracking_bug,$release_label,@releases);
    my $status_prority = '34529,34524';

    #
    # Fetch latest Release Candidate(RC 34529), if no RC availble , then latest Release(34524)
    #
    my ($comp_series_names) = ARUDB::exec_sf('aru_cumulative_request.get_series_attribute_value', $series_id, 'SPB_COMPONENT_CPM_SERIES');
    ISD::Text::strip_whitespace(\$comp_series_names);

    foreach my $comp_series_pair (split(',', $comp_series_names)) {

        my ($comp_name, $comp_series_name) = ($comp_series_pair =~ /(.*):(.*)/);
        ISD::Text::strip_whitespace(\$comp_name);
        ISD::Text::strip_whitespace(\$comp_series_name);
        next unless($comp_series_name && $comp_name && lc $comp_series_name =~ /Stack Patch Bundle/i);

        my ($comp_series_id) = ARUDB::exec_sf('aru_cumulative_request.get_series_id',$comp_series_name);

        foreach my $status_id (split(',', $status_prority)) {
            my $records = ARUDB::query('GET_ORDERED_CPM_RELEASES',$comp_series_id, $status_id);

            foreach my $record (@$records) {    
                $release_id      = $record->[8];
                $release_name    = $record->[2];
                $tracking_bug    = $record->[9];
                $release_label   = $record->[10];
                $self->{log_fh}->print("Release Name $release_name ,Tracking Bug $tracking_bug , Release Label $release_label\n");
                last if ($tracking_bug);
            }

            last if ($tracking_bug); 
        }
        push(@releases,{release_id => $release_id, 
                        release_name => $release_name,
                        tracking_bug => $tracking_bug,
                        release_label => $release_label});

    }

    $self->{log_fh}->print("get_unique_values function: " . Dumper(@releases) . "\n");

    return @releases;
}

sub set_comp_patches {
    my ($self,@releases) = @_;

    my (@binary_patches_lis,@tool_patches_lis,@config_patches_lis);
    my %patches = ();
    $patches{spb_binary_patches} = {'aru'=>ARU::Const::spb_binary_patches_aru,
                                    'loc'=>ARU::Const::spb_binary_patches_location,
                                    'val'=>[]};
    $patches{spb_tool_patches} = {'aru'=>ARU::Const::spb_tool_patches_aru,
                                    'loc'=>ARU::Const::spb_tool_patches_location,
                                    'val'=>[]};
    $patches{spb_config_patches} = {'aru'=>ARU::Const::spb_config_patches_aru,
                                    'loc'=>ARU::Const::spb_config_patches_location,
                                    'val'=>[]};

    foreach my $release (@releases){
        my ($bugfix_id) = ARUDB::single_column_query("GET_SPB_BUGFIX_ID",$release->{tracking_bug},$release->{release_id});
        next unless ( $bugfix_id);

        foreach my $type (keys %patches) {
            my $patch_type = $patches{$type};

            my ($comp_patches) = ARUDB::exec_sf('aru_bugfix_attribute.get_bugfix_attribute_value', 
                                    $bugfix_id,$patch_type->{aru});
            push(@{$patch_type->{val}},$comp_patches) if($comp_patches);
            
            my ($comp_patches_loc) = ARUDB::exec_sf('aru_bugfix_attribute.get_bugfix_attribute_value', 
                                        $bugfix_id,$patch_type->{loc}) if($self->{$type."_location"});

            $self->{$type."_location"} ||= $comp_patches_loc;
                                
        }

    }

    my ($overide_patches) = ARUDB::exec_sf('aru_cumulative_request.get_series_attribute_value',
                                            $self->{spb}->{series_id}, 'SPB_OVERIDE_PATCHES');
    $overide_patches||='';
    $self->{log_fh}->print("overide_patches   $overide_patches series_id $self->{spb}->{series_id}\n");

    foreach my $type (keys %patches) {
        my $patch = $patches{$type};
        my $patch_lis =join(",",@{$patch->{val}});
        $self->{$type."_aru"}  = $self->get_overide_patch_lis($overide_patches,$patch_lis);
    
    }

    $self->{log_fh}->print("set_comp_patches spb_binary_patches_aru  $self->{spb_binary_patches_aru}  \n");
    $self->{log_fh}->print("set_comp_patches spb_tool_patches_aru    $self->{spb_tool_patches_aru}  \n");
    $self->{log_fh}->print("set_comp_patches spb_config_patches_aru  $self->{spb_config_patches_aru}  \n");

}


sub get_overide_patch_lis {
    my ($self, $overide_patches,$patches)= @_;
    $overide_patches=~ s/^\s+|\s+$//g;
    $patches=~ s/^\s+|\s+$//g;
    my @patch_lis = split(',',$patches);
    my @result_patch_lis;
    print("Before overide patches $patches\n");
    foreach my $patch (@patch_lis){
        my ($comp,$aru) = split(':',$patch);
        next if($overide_patches =~/^$comp$|^$comp,|$comp$|,$comp,/);
        push(@result_patch_lis,$patch);
    }
   return join(",", @result_patch_lis);
}

sub download_component_patches {

    my ($self) = @_;

    my $log_fh = $self->{log_fh};
    my $system = $self->{system};
    my $work_area = $self->{work_area};
    my $spb = $self->{spb};
    my $generic_patchlist;
    my $is_spbat_included = 0;
    my $binary_patch_path;
    my @platforms;
    my $spb_platform_map = PB::Config::spb_platform_map;
    my @binary_patch_ids;
    my ($patchlist_prods) = ARUDB::exec_sf('aru_parameter.get_parameter_value','SPB_PATCH_LIST_PRODS');

    $system->do_chdir($work_area);

    #
    # Clear any existing patch dir from any retries
    #
    $system->do_cmd_ignore_error("rm -rf $work_area/$spb->{repo_name}");

    $self->{msg} = "";

    my $cmd;
    my ($comp_aru, $comp_tracking_bug, $comp_name, $comp_patch_loc, $patch_type, $patch_platform);
    foreach my $patch (@{$self->{spb}->{patches}}) {
   eval{  
        $log_fh->print('=' x 100, "\n\n");
        $comp_aru = $patch->{aru_no};
        $comp_name = $patch->{comp_name};
        $comp_tracking_bug = $patch->{tracking_bug};
        $patch_type = $patch->{type};
        $patch_platform = $patch->{platform};

        $comp_patch_loc = $work_area . "/" . $patch->{patch_loc};
        $system->do_mkdir($comp_patch_loc,0755);

        $log_fh->print("\n\n==>Component patch details: Component:$comp_name, ARU:$comp_aru, Tracking Bug:$comp_tracking_bug\n");
        $log_fh->print("Downloading $patch_type for $comp_name\n");
        #
        # Get the bug abstract.
        #
        $log_fh->print("Fetching bug information of Bug: $comp_tracking_bug \n");
        my ($return_code, $return_msg, $bug_abstract) =
            BUGDB::get_bug_info($comp_tracking_bug);

        #Set bug abstract in the hash
        $patch->{bug_abstract} = $bug_abstract;

        $self->{msg} .= "Bug $comp_tracking_bug $bug_abstract ARU $comp_aru\n";
        #
        # download the patch
        #
        my $timeout = 600;
        $self->{system}->do_cmd_ignore_error("cp /scratch/rchamant/prod/dummy_patch/p33093748_122140_Generic.zip  $comp_patch_loc/$comp_tracking_bug.zip");
        my $zip_file = "$comp_tracking_bug.zip";

        my $comp_patch_file = "$comp_patch_loc/$zip_file";
        $log_fh->print("Patch file is : $comp_patch_file \n");
        unless (-f $comp_patch_file) {
            die("Unable to download mandatory patch for $comp_aru " .
                " - $comp_patch_file \n");
        }

        $system->do_chmod(0755,$comp_patch_file);

        #
        #check if patch is spbat and unzip the contents
        #
        if ($comp_name eq 'spbat') {
            $is_spbat_included = 1;
            $log_fh->print("Unzipping spbat tool patch\n");
            $system->do_chdir($comp_patch_loc);
            $cmd = "chmod 777 $zip_file";
            $self->_exec_command
                (do_cmd_obj => $self->{system},
                    method  => 'do_cmd_ignore_error',
                    args    => [ $cmd, (keep_output => 'YES',
                        timeout                     => PB::Config::ssh_timeout) ]);

            $cmd = "/usr/bin/unzip -o $zip_file";
            $self->process_cus_or_unzip_cmd({cmd=>$cmd});


            $cmd = "rm $zip_file";
            $self->process_cus_or_unzip_cmd({cmd=>$cmd});

            $system->do_chdir($work_area);
        }


        #
        # Extract oig(oim) Readme from oim latest bundle patch
        # and place under etc
        #

        if ($self->{spb}->{cpm_product_name} eq 'IDM' && $comp_name eq 'oig' && $patch_type eq 'binary') {
            my ($series_name, $release_name);
            eval {
                ARUDB::exec_sp
                    ('aru_cumulative_request.get_tracking_bug_details',
                        $comp_tracking_bug, \$series_name, \$release_name);
            };
            if (defined($patch->{series_name}) || $series_name ne "") {
                $log_fh->print("Extracting latest oim(oig) readme from the binary oim component bundle " . $patch->{series_name}."\n");
                my $oim_readme_loc = "$comp_tracking_bug/README.html";
                my $readme_output_loc = "$spb->{repo_name}/etc";
                $system->do_mkdir($readme_output_loc,0755);
                $cmd = "unzip -j $comp_patch_file $oim_readme_loc -d $readme_output_loc";
                $self->{system}->do_cmd_ignore_error($cmd);

                unless(-f "$readme_output_loc/README.html") {
                    $cmd = "unzip -j $comp_patch_file '*/README.html' -d $readme_output_loc";
                    $self->{system}->do_cmd_ignore_error($cmd);
                }
                #
                #Rename readme to OIG_README.html
                #
                $cmd = "mv -f $readme_output_loc/README.html $readme_output_loc/OIG_Bundle_Patch_Readme.html";
                $self->{system}->do_cmd_ignore_error($cmd);
            }

        }

        #
        # Fetch spb_jdk_info.json from jdk patch
        #
        if ($comp_name eq 'jdk' && $patch_type eq 'tool') {

            #
            # Remove jdk patch from bug update as patch is internal patch and not part of SPB
            #

            $self->{msg} =~ s/Bug $comp_tracking_bug $bug_abstract ARU $comp_aru\n//g;

            $log_fh->print("Fetching spb_jdk_info.json metadata file from ARU: $comp_aru\n");
            $system->do_chdir($comp_patch_loc);
            $cmd = "chmod 777 $zip_file";
            $self->_exec_command
                (do_cmd_obj => $self->{system},
                    method  => 'do_cmd_ignore_error',
                    args    => [ $cmd, (keep_output => 'YES',
                        timeout                     => PB::Config::ssh_timeout) ]);

            $cmd = "unzip -j $comp_patch_file '*spb_jdk_info.json'";
            $self->process_cus_or_unzip_cmd({cmd=>$cmd});

            #
            # Verify json exists and its validity
            #
            if (-f "$comp_patch_loc/spb_jdk_info.json") {
                $self->{system}->do_chmod(0755, "$comp_patch_loc/spb_jdk_info.json");
                my $jdk_json_fh = new FileHandle("< $comp_patch_loc/spb_jdk_info.json");
                my @lines = $jdk_json_fh->getlines();
                my $jdk_json = join("\n", @lines);
                $jdk_json_fh->close();
                eval {decode_json($jdk_json)};
                if ($@) {
                    die("spb_jdk_info.json file is invalid. Verify json file contents in jdk patch under SPB_TOOL_PATCHES_ARU series parameter");
                }
            }


            $cmd = "rm $zip_file";
            $self->process_cus_or_unzip_cmd({cmd => $cmd});

            $system->do_chdir($work_area);

        }


        if ($comp_name eq 'opatch') {
            #
            # Populated in readme
            #
            $self->{spb}->{spb_opatch_zip} = $zip_file;
        }

        #
        # For generic SPBs(except IDM), create patchlist file for each platform listing all patches for that platform
        # Generic patches are part of all platform files
        #
        if($self->{spb}->{cpm_product_name} =~/$patchlist_prods/ && $patch_type eq 'binary')
        {
            #
            # Split the binary patch loc path and create files for all platforms
            #
            #
            my ($file_path,$patchzip_rel_path) = split("\/$comp_name\/", $comp_patch_file);
            $patchzip_rel_path = $comp_name."/".$patchzip_rel_path;
            (my $patch_rel_parent_path = $patchzip_rel_path) =~ s/$zip_file//;
            $binary_patch_path = $file_path;
            if($comp_name ne 'coherence')
            {
                push(@binary_patch_ids, $comp_tracking_bug);
            }
            else
            {
                #
                # For coherence patches patch id is different than tracking bug for 12cPS3, 12cPS4
                #
                $cmd = "unzip -l $comp_patch_file | awk 'NR==4{print \$4}' | sed 's/\\///g'";
                $self->exec_retry_command
                    (do_cmd_obj => $self->{system},
                        method  => 'do_cmd_ignore_error',
                        args    => [ $cmd, (keep_output => 'YES',
                            timeout                     => PB::Config::ssh_timeout) ]);

                my @output = $self->{system}->get_last_do_cmd_output();
                my $patch_id = $output[0];
                chomp($patch_id);
                ISD::Text::strip_whitespace(\$patch_id);
                unless($patch_id =~ /^[0-9]+$/)
                {
                    die("Failure while creating rollback_patchlist.txt. Unable to fetch patch id for coherence patch.");
                }
                push(@binary_patch_ids, $patch_id);

            }
            $log_fh->print("Patch Relative Path list in text file is: ".$patch_rel_parent_path."\n");

                if(lc($spb_platform_map->{$patch_platform}) eq 'generic')
                {
                    $generic_patchlist .= $patch_rel_parent_path."\n";

                }
                else
                {
                    push (@platforms,$patch_platform);
                    my $path = $file_path."/".lc($spb_platform_map->{$patch_platform})."_patchlist.txt";
                $log_fh->print("$path files is created and $patch_rel_parent_path is added"."\n");
                    my $patchlist_fh = new FileHandle(">> $path");
                    $patchlist_fh->print($patch_rel_parent_path);
                    $patchlist_fh->print("\n");
                    $patchlist_fh->close();
                }

        }

    #  Unzip binary-patches & place under same parent path remove the extracted zip, see 33806441 for more info    
        if($patch_type eq 'binary')
        {
            $self->process_cus_or_unzip_cmd({src_file=>$comp_patch_file,
                                                dest_loc =>$comp_patch_loc,
                                                keep_output=>'NO'});
            $system->do_cmd_ignore_error("rm -f $comp_patch_file");
        }
    };
    }

    #
    # Create patchlist file for each platform listing all patches for that platform
    # Generic patches will be part of all platform files
    #
    if($self->{spb}->{cpm_product_name} =~/$patchlist_prods/)
    {
        #
        # Fixed list of platforms for which file has to be generated
        # 289 is added to create generic patchlist as per ENH 32736268
        #

        my $supported_platforms_list;
        eval {
            $supported_platforms_list = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                $self->{spb}->{cpm_product_name} . '_SPB_SUPPORTED_PLATFORMS');
        };
        #
        # Supported platform list not set : generic_patchlist has to be created.
        #
        if(!$supported_platforms_list) {
            push(@platforms, $self->{aru_obj}->{platform_id});
        }

        # Adding Patch platform into platforms list, as it is required to create patchlist.txt file
        push(@platforms, $self->{aru_obj}->{platform_id});

        @platforms =  uniq(@platforms);
        foreach my $platform (@platforms) {
            my $path = $binary_patch_path . "/" . lc($spb_platform_map->{$platform}) . "_patchlist.txt";
            my $patchlist_fh = new FileHandle(">> $path");
            #
            # Add generic patches to all platforms patch list
            #
            $patchlist_fh->print($generic_patchlist);
            $patchlist_fh->close();
            $self->{system}->do_chmod(0755, "$path");
        }

        #
        # Create rollback_patchlist.txt
        #
        $log_fh->print("\nCreating rollback_patchlist.txt\n");
        my $path = $binary_patch_path . "/rollback_patchlist.txt";
        $self->{spb}->{rollback_patchlist_path} = $path;
        my $patchlist_fh = new FileHandle(">> $path");
        my @uniq_patch_ids = uniq(@binary_patch_ids);
        $patchlist_fh->print(join("\n", @uniq_patch_ids) . "\n");
        $patchlist_fh->close();
        $self->{system}->do_chmod(0755, "$path");
    }


    #
    # If json file inclusion param is set, then check if spb_jdk_info.json is present or not
    # Check can be skipped if spbat tool is not part of patch. As only spbat tools need this file.
    #
    my @spb_jdk_json_required;
    eval{
        @spb_jdk_json_required = split(',',ARUDB::exec_sf("aru_parameter.get_parameter_value",
        'SPB_JDK_JSON_REQUIRED'));
    };
    if($is_spbat_included && grep(/$self->{spb}->{cpm_product_name}/,@spb_jdk_json_required)){
        #
        # Check if spb_jdk_info.json exists
        #
        my $json_file_path = $self->{spb}->{tool_patches_location};
        $json_file_path =~ s/\[[platform^\]]*\]/generic/g;
        $json_file_path =~ s/\[[repo_name^\]]*\]/$self->{spb}->{repo_name}/g;
        $json_file_path =~ s/\[[component^\]]*\]/jdk/g;
        $log_fh->print("spb_jdk_json file location is : $work_area/$json_file_path/spb_jdk_info.json\n");
        unless(-f "$work_area/$json_file_path/spb_jdk_info.json")
        {
            die("spb_jdk_info.json doesn't exist. Verify if file exists in jdk patch under SPB_TOOL_PATCHES_ARU series parameter");
        }

    }
    $log_fh->print("Printing bug update message : $self->{msg}\n");

}


sub get_latest_component_patch() {

    my ($self, $comp_series_name) = @_;
    my $log_fh = $self->{log_fh};


    my ($comp_series_id) = ARUDB::exec_sf('aru_cumulative_request.get_series_id',
        $comp_series_name);

    die("Series $comp_series_name provided in SPB_COMPONENT_CPM_SERIES not found.")
        unless($comp_series_id);

    $log_fh->print('=' x 100, "\n");
    $log_fh->print("Component Series name: $comp_series_name, Series id is: $comp_series_id\n");

    my ($rank, $comp_aru, $sub_base_bug, @rest);
    my ($release_id, $release_version, @others);
    my $status_prority = '34529,34524';
    #
    # Fetch latest RC, if no RC availble , then latest Released
    #
    foreach my $status_id (split(',', $status_prority)) {
        last if ($comp_aru);
        #
        # Get all releases having status_id
        #
        my $records = ARUDB::query('GET_ORDERED_CPM_RELEASES',
            $comp_series_id, $status_id);

        foreach my $record (@$records) {

            ($release_id, $release_version, @others) = @$record;

            $log_fh->print("$status_id Release is $release_id, $release_version\n");


            ($rank, $comp_aru, $sub_base_bug, @rest) =
                ARUDB::single_row_query('GET_LATEST_SPB_COMPONENT_PATCH',
                    $release_id);

            $log_fh->print("Latest component bug for $comp_series_name is :$sub_base_bug\n");

            last if ($comp_aru);
        }
    }

    $log_fh->print("Unable to find the ARU for $comp_series_name\n")
        unless ($comp_aru);

    return $comp_aru;

}

sub process_comp_series_parameters {
    my ($self, $comp_series_pairs, $comp_location, $comp_type) = @_;
    if ($comp_series_pairs eq "") {
        return;
    }
    die("SPB_" . uc($comp_type) . "_PATCHES_LOCATION not provided in series configuration")
        unless ($comp_location);

    ISD::Text::strip_whitespace(\$comp_series_pairs);


    my $log_fh = $self->{log_fh};


    foreach my $comp_series_pair (split(',', $comp_series_pairs)) {

        $log_fh->print('=' x 100, "\n\n");
        #
        # Get platform specific patch ARU if available
        #
        my ($comp_name, $comp_series_name) = ($comp_series_pair =~ /(.*):(.*)/);
        ISD::Text::strip_whitespace(\$comp_name);
        ISD::Text::strip_whitespace(\$comp_series_name);

        next unless(($comp_series_name || $comp_name) && 
                    (lc $comp_series_name !~ /Stack Patch Bundle/i));

        die("Invalid value - \"$comp_name:$comp_series_name\" in SPB_COMPONENT_CPM_SERIES Series Attribute")
            unless($comp_series_name && $comp_name);

        $comp_name = lc($comp_name);
        my $comp_aru = $self->get_latest_component_patch($comp_series_name);

        #
        # If there is no latest patch, then skip the series
        #
        next unless ($comp_aru);

        $log_fh->print("ARU for $comp_name is : $comp_aru\n");

        $self->fetch_comp_patches_data($comp_name,$comp_type,$comp_aru,$comp_location,$comp_series_name);

    }

}

sub process_comp_aru_parameters {

    my ($self, $comp_aru_pairs, $comp_location, $comp_type) = @_;
    if ($comp_aru_pairs eq "") {
        return;
    }
    die("SPB_" . uc($comp_type) . "_PATCHES_LOCATION not provided in series configuration")
        unless ($comp_location);


    ISD::Text::strip_whitespace(\$comp_aru_pairs);


    my $log_fh = $self->{log_fh};
    $log_fh->print("ARU List: $comp_aru_pairs\n\n");

    foreach my $comp_aru_pair (split(',', $comp_aru_pairs)) {

        $log_fh->print('=' x 100, "\n\n");
        my ($comp_name, $comp_aru) = ($comp_aru_pair =~ /(.*):(.*)/);
        ISD::Text::strip_whitespace(\$comp_name);
        ISD::Text::strip_whitespace(\$comp_aru);

        next unless($comp_aru || $comp_name);

        die("Invalid value - \"$comp_name:$comp_aru\" in SPB_".uc($comp_type)."_PATCHES_ARU Series Attribute")
            unless($comp_aru && $comp_name);

        $comp_name = lc($comp_name);
        $log_fh->print("ARU for $comp_name is : $comp_aru\n");
        $self->fetch_comp_patches_data($comp_name,$comp_type,$comp_aru,$comp_location,'');

   }
}

sub fetch_comp_patches_data {

    my ($self, $comp_name,$comp_type,$comp_aru,$comp_location,$comp_series_name) = @_;
    my $log_fh = $self->{log_fh};

    $log_fh->print("SPB Platform is : $self->{aru_obj}->{platform} \n");


    #
    # For generic SPBs, all platform patches for non-generic patches have to be fetched.
    # spb is generic, then enter if
    #
    if($self->{aru_obj}->{platform_id} == 2000)  # && !grep( /^2000$/, @platforms )
    {
        $log_fh->print("Fetching platform patches for $comp_name for $self->{spb}->{cpm_product_name} SPB\n");
        #
        # Get all distinct platforms for the component patch
        #
        my @platforms =  ARUDB::query('GET_ALL_PATCH_PLATFORMS',
            $comp_aru);
        if(scalar(@platforms) == 0)
        {
            die("Patch for $self->{aru_obj}->{platform} platform not available for \"$comp_name:$comp_aru\" provided in SPB_".uc($comp_type)."_PATCHES_ARU Series Attribute");

        }

        #
        # If platform is not generic, and there is constant platform list available in parameters
        # for the SPB product, then use constant platform list, otherwise all platforms are supported
        #
        if(!grep( /^2000$/, $platforms[0][0])){

        my $supported_platforms_list;
            eval{
            $supported_platforms_list= ARUDB::exec_sf("aru_parameter.get_parameter_value",
            $self->{spb}->{cpm_product_name}.'_SPB_SUPPORTED_PLATFORMS');};

        if($supported_platforms_list) {
            $log_fh->print("Supported platform list configured in $self->{spb}->{cpm_product_name}"."_SPB_SUPPORTED_PLATFORMS parameter for $self->{spb}->{cpm_product_name} SPB is
        : $supported_platforms_list \n");
            my @supported_platforms = split(',', $supported_platforms_list);
            @platforms = @supported_platforms;
        }

        }

        foreach my $p (@platforms)
        {
            my $platform = $p;
            if(ref($p) eq 'ARRAY') {
                ($platform) = @$p;
            }
            my ($aru, $platform1, $bug_number) = ARUDB::single_row_query('GET_GENERIC_OR_PLATFORM_ARU',
                $comp_aru, $platform);
            die("Patch for $platform platform not available for \"$comp_name:$comp_aru\" provided in SPB_".uc($comp_type)."_PATCHES_ARU Series Attribute")
                unless ($aru);
            $self->set_patch_data( $comp_location,$comp_name,$comp_type, $aru, $platform1, $bug_number, $comp_series_name);
            $log_fh->print('=' x 100, "\n");
        }


    }
    else {
        my ($aru, $platform, $bug_number) = ARUDB::single_row_query('GET_GENERIC_OR_PLATFORM_ARU',
            $comp_aru, $self->{aru_obj}->{platform_id});
        #
        # Die, if no ARU found in the system
        #
        die("Patch for $self->{aru_obj}->{platform} platform not available for \"$comp_name:$comp_aru\" provided in SPB_" . uc($comp_type) . "_PATCHES_ARU Series Attribute")
            unless ($aru);

        $self->set_patch_data($comp_location, $comp_name, $comp_type, $aru, $platform, $bug_number, $comp_series_name);

    }


}

sub set_patch_data {

    my ($self, $comp_location,$comp_name,$comp_type, $aru, $platform, $bug_number, $series_name) = @_;
    my $log_fh = $self->{log_fh};
    my $spb_platform_map = PB::Config::spb_platform_map;
    my $str_platform = lc($spb_platform_map->{$platform});
    $log_fh->print("Platform is : $str_platform\n");
    my $loc = $comp_location;
    $loc =~ s/\[[platform^\]]*\]/$str_platform/g;
    $log_fh->print("After replacing platform Location is: $loc\n");
    $loc =~ s/\[[repo_name^\]]*\]/$self->{spb}->{repo_name}/g;
    $log_fh->print("After replacing repo Location is: $loc\n");
    $loc =~ s/\[[component^\]]*\]/$comp_name/g;
    $log_fh->print("After replacing component Location is: $loc\n");

    my %component_patch;
    $component_patch{'aru_no'} = $aru;
    $component_patch{'patch_loc'} = $loc;
    $component_patch{'platform'} = $platform;
    $component_patch{'tracking_bug'} = $bug_number;
    $component_patch{'comp_name'} = $comp_name;
    $component_patch{'type'} = $comp_type;
    $component_patch{'series_name'} = $series_name;

    push @{$self->{spb}->{patches}}, \%component_patch;

    # $self->{"spb_".$comp_type."_patches_aru"} = $self->get_unique_values("$comp_name:$aru",$self->{"spb_".$comp_type."_patches_aru"});
    # $log_fh->print("Details from set patch data for $comp_type \n".$self->{"spb_".$comp_type."_patches_aru"});

    #
    # register the component patch and spb details
    #

    my $series_id;
    $series_id = ARUDB::exec_sf('aru_cumulative_request.get_series_id',$series_name)
        if($series_name);
    eval{

      ARUDB::exec_sp("aru.apf_spb_patch_detail.insert_component_patch_detail",
          $self->{spb}->{series_id},
          $series_id,
          $self->{spb}->{tracking_bug}
          ,$bug_number,
           $aru,
          $self->{aru_obj}->{aru},
          $comp_type,
          $comp_name,
           $self->{request_id},
           $self->{aru_obj}->{platform_id},
          ARU::Const::apf_userid, "$self->{spb}->{repo_name} requested at $self->{localtime}" );
   };


   $log_fh->print("Registered  ** $comp_name : $bug_number : ARU $aru **  to Stack Patch ARU : $self->{aru_obj}->{aru}\n");
}

sub get_component_patches {

    my ($self, $tracking_bug) = @_;
    my $log_fh = $self->{log_fh};

    my ($series_name, $release_name);
    ARUDB::exec_sp
        ('aru_cumulative_request.get_tracking_bug_details',
            $tracking_bug, \$series_name, \$release_name);

    $log_fh->print("Stack Patch series name is:$series_name:\n\n");
    my ($series_id) = ARUDB::exec_sf('aru_cumulative_request.get_series_id',
        $series_name);
    $log_fh->print("Series id is: $series_id\n");
    # my @releases = $self->get_latest_comp_releases($series_id);
    # $self->set_comp_patches(@releases);
    $self->get_binary_patches_details($series_id);
    $self->get_config_patches_details($series_id);

    #
    # If there are no patches for binary and config then die as nothing needs to be packaged.
    #
    die("No component patches available for Stack Patch Bundle")
        unless (exists($self->{spb}->{patches}));

    $self->get_tool_patches_details($series_id);

    $log_fh->print("\n\nPatch List: \n" . Dumper($self->{spb}->{patches})."\n\n");

}

sub generate_info_patch {
    my ($self) = @_;
    my $error;
    my $log_fh =$self->{log_fh};
    my @base_bugs = ();
    my $platform_id = $self->{aru_obj}->{platform_id};
    my $oldworkdir = `pwd;`;
    chomp($oldworkdir);
    my $work_area = $self->{work_area};
    $self->{system}->do_chdir($work_area);
    $log_fh->print('=' x 100, "\n\n");
    $log_fh->print("Creating a bug to track Stack Patch Bundle tracker patch \n");
    my ($new_bug,$bughash,$subject) = $self->generate_tracking_bug();
    $bughash->{pv_abstract} =~s/\(Interim Patch \d+\)//ims;
    $bughash->{pv_abstract} =~s/^\s+|\s+$//;
    push(@base_bugs,"\"$new_bug:$bughash->{pv_abstract}\"");

    eval{
        my ($param_name,$prev_aru_no)  = ARUDB::single_row_query('GET_PREVIOUS_SPB_TRACKING_ARU',$self->{spb}->{series_id},"SPB_TRACKER_PLAT:$platform_id:");
        $log_fh->print("Previous Stack Patch Bundle  Tracker patch ARU no $prev_aru_no \n");
        my $prev_aru_obj      = ARU::BugfixRequest->new($prev_aru_no);
        my $prev_bugfix =  $prev_aru_obj->get_bugfix();
        foreach my $fixed_bug (@{$prev_bugfix->get_fixed_direct_bugs()})
            {
                my ($bug) = @$fixed_bug;
                my ($return_code, $return_msg, $abstract,@rest) = BUGDB::get_bug_info($bug);
                $abstract =~s/\(Interim Patch \d+\)//ims;
                $abstract =~s/^\s+|\s+$//;
                push(@base_bugs,"\"$bug:$abstract\"");
            }
        $log_fh->print("Fetched following fixed bugs from previous patch \n",join("\n",@base_bugs),"\n");
    };

    # create spb_info txt file and add content
    $log_fh->print("Creating spb_info txt file \n") if($new_bug);
    my $info  = lc $self->{spb}->{cpm_product_name}."_spb_info.txt";
    my $info_fh  = new FileHandle("> $info");
    my (@spb_info_contents_lis) = $self->{msg} =~/^(.*?)ARU \d+$/gms;
    my $spb_info_contents = join("\n", @spb_info_contents_lis);
    $info_fh->print("$subject Content \n");
    $info_fh->print('=' x 100, "\n\n");
    $info_fh->print("$spb_info_contents\n");
    $info_fh->close();
    $self->{system}->do_chmod(0755, $info);

    #generate template file
    my $oui_comp_str =`grep '"oracle.wls.core.app.server"' $self->{spb}->{repo_name}/binary_patches/wls/*/*/etc/config/inventory.xml`;
    my $oui_ver = $1 if($oui_comp_str=~/(?<=version)\D+([0-9\.]+)/);
    my %tmpl_params = ();
    $tmpl_params{bug}  = $new_bug;
    $tmpl_params{sub}  = $bughash->{pv_abstract};
    $tmpl_params{oui_ver}  = $oui_ver;
    $tmpl_params{info_file} = $info;
    $tmpl_params{base_bugs} = join(",", @base_bugs);
    my $tmpl                = "$self->{spb}->{cpm_product_name}\_$new_bug.tmpl";
    $self->generate_template($tmpl,%tmpl_params);

    # Pack spb_info txt into opatchable zip using opack
    my $path = $self->generate_info_zip($tmpl,$new_bug);

    # remove created spb_info txt as no longer required
    $self->{system}->do_cmd_ignore_error("rm -rf $info");

    #Copy created zip wls/generic location, and original one is used by RL in uploadinf tracking patch
    eval{
        $self->{system}->do_mkdir($self->{spb}->{repo_name}."/binary_patches/wls/generic",0755);
        my $mv_cmd = "mv $path $self->{spb}->{repo_name}/binary_patches/wls/generic/";
        $self->{system}->do_cmd_ignore_error($mv_cmd);
    };


    # Upload this SPB tracking patch using uploadcli
    my $upld_params = {};
    $upld_params->{bug} = $new_bug;
    $upld_params->{product_name} = $self->{aru_obj}->{product_name};
    $upld_params->{release_name} = $self->{aru_obj}->{release_long_name};
    $upld_params->{update_bugs} = $new_bug;
    $upld_params->{abstract} =  $bughash->{pv_abstract};
    $upld_params->{file} = $path.".zip";

    my $tracking_aru = $self->upload_patch($upld_params);

    #seed this tracking patch information in aru_series_parameters useful for next run
    my @input_params = ({name => "pn_series_id" , data=>$self->{spb}->{series_id}},
                        {name => "pv_parameter_name",data=>"SPB_TRACKER_PLAT:$platform_id:$self->{aru_obj}->{bug}"},
                        {name => "pn_parameter_type",data=>96505},
                        {name => "pv_parameter_value" ,data => $tracking_aru});

    my $error = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters',@input_params ) if($tracking_aru);
    $log_fh->print("Details of Tracker patch seeded with Series") if($error);

    $path = $self->{spb}->{rollback_patchlist_path};
    my $patchlist_fh = new FileHandle(">> $path");
    $patchlist_fh->print("$new_bug\n") if($new_bug);
    $patchlist_fh->close();

    # Change back to old Directory
    $self->{system}->do_chdir($oldworkdir);

    return $upld_params->{file};

}

sub generate_template {
    my ($self,$tmpl,%params) = @_;

    my $log_fh =$self->{log_fh};
    $log_fh->print('=' x 100, "\n\n");
    my $tmpl_fh  = new FileHandle("> $tmpl");
    $log_fh->print("Generating template file $tmpl\n");
    my ($template_version)  =   ARUDB::exec_sf('aru_cumulative_request.get_series_parameter_value',0,'SPB_TEMPLATE_VERSION' );
    $template_version ||="1.0.0";
    my ($min_opatch_ver) = ARUDB::single_row_query('GET_SERIES_REQ_ATTRIBUTE',$self->{spb}->{series_id},'SPBAT_SPB_MIN_OPATCH_VERSION','Y');
    # printing [GENERAL] data
    $tmpl_fh->print("[General]\n");
    $tmpl_fh->print("TEMPLATE_FILE_VERSION=\"$template_version\"\n");

    # [Data]
    $tmpl_fh->print("[Data]\n");
    $tmpl_fh->print("PATCHSET_EXCEPTION_NUMBER=$params{bug}\n");
    $tmpl_fh->print("PATCH_DESCRIPTION=\"$params{sub}\"\n");
    $tmpl_fh->print("PLATFORMS={0}\n");
    $tmpl_fh->print("PRODUCT_FAMILY=\"fmw\"\n");
    $tmpl_fh->print("MINIMUM_OPATCH_VERSION=\"$min_opatch_ver\"\n");
    $tmpl_fh->print("PATCH_TYPE=\"singleton\"\n");
    $tmpl_fh->print("INSTANCE_SHUTDOWN=true\n");
    $tmpl_fh->print("COMPONENT=\"oracle.wls.core.app.server:$params{oui_ver}:O\"\n");
    $tmpl_fh->print("BASE_DIR=\"./\"\n");
    # [Base Bugs Data]
    $tmpl_fh->print("BASE_BUGS={$params{base_bugs}}\n");
    # [Actions]
    $tmpl_fh->print("[Actions]\n");
    $tmpl_fh->print("COPY_LIST={\"./:$params{info_file}\"}\n");
    $tmpl_fh->close();
    $log_fh->print("Generated template file $tmpl\n");
    $log_fh->print('=' x 100, "\n\n");

}

sub generate_tracking_bug {
    my ($self) = @_;
    my $log_fh =$self->{log_fh};
    # create a bug to track info patch
    my ($src_bug,$error) = $self->get_full_bug_info($self->{aru_obj}->{bug});

    my $bughash = {};
    $bughash->{pn_product_id} = $src_bug->{product_id};
    $bughash->{pv_component}  = $src_bug->{component};
    $bughash->{pn_product_line_id}  = 226;
    $bughash->{pn_cs_priority}  = 2;
    $bughash->{pv_utility_version}  = $src_bug->{component_version};
    $bughash->{pv_abstract}     = "$src_bug->{subject} (Patch $self->{aru_obj}->{bug}) (Interim Patch $self->{pse})";
  
    my @binds =();
    for my $key (keys %{$bughash}) {
      $log_fh->print("$key $bughash->{$key} \n");
      push(@binds,{name=>$key,data=>$bughash->{$key}});
    } 
    my $new_bug = ARUDB::exec_sf("bugdb.create_bug",@binds);
    $log_fh->print("SPB Tracker patch bug created successfully $new_bug \n") if($new_bug);
 
    return ($new_bug,$bughash,$src_bug->{subject});
}

sub generate_info_zip {
    my ($self,$tmpl,$new_bug) = @_;
    my $log_fh =$self->{log_fh};
    my $work_area = $self->{work_area};

    #Run Opack command on to generate opack zip
    my $opack_cmd = "perl /ade_autofs/gr31_dbem/OPACK_14.1.0_GENERIC.rdd/RELEASE_14.1.0.1.11/opack/OPack/opack package -t ";
    $opack_cmd .=$tmpl;
    $self->process_cus_or_unzip_cmd({cmd=>$opack_cmd,keep_output=>'YES'});
    my $path = "$work_area/$new_bug";
    $self->process_cus_or_unzip_cmd({cmd=>"rm $tmpl"});

    #create a readme for this info patch inside folder
    my $readme_info_fh  = new FileHandle("> $work_area/$new_bug/README.txt");
    $readme_info_fh->print("This Patch is to track content delivered in current Stack Patch Bundle");
    $readme_info_fh->close();

    #Remove existing zip & update the folder with new readme.txt in it & recreate zip
    $self->{system}->do_cmd_ignore_error("rm -rf $new_bug.zip");
    $log_fh->print("Update the created folder with new README.txt in it \n") if($new_bug);
    $self->{system}->do_cmd_ignore_error("zip -r $new_bug.zip $new_bug");

    #update the zip with new permissions to it.
    $log_fh->print("Update the zip with new permissions to it \n") if($new_bug);
    $self->{system}->do_chmod(0755, "$path.zip");
    $self->{system}->do_chmod(0755, "$path");

    return $path;
}

sub upload_patch {
    my ($self,$params) = @_;
    my $tracking_aru;

    $params->{platform_name} ||= 'Generic Platform';
    $params->{language_code} ||= 'US';
    $params->{patch_type} ||= 'Standalone Checkin';
    $params->{dist_type} ||= 'Not Distributed';
    $params->{ftp_username} ||= PB::Config::upload_ftp_user_name;
    $params->{ftp_password} ||= PB::Config::upload_ftp_password;
    $params->{ftp_mode} ||= "sftp";
    # $params->{upload_user} ||=  'apfmgr';
    $params->{comment} ||= "Uploading for " . $params->{bug}; 
    my $host_name = `hostname -f`;
    chomp($host_name);
    $params->{machine} ||= $host_name;

    my ($upload_config) = ARUDB::exec_sf('aru_parameter.get_parameter_value','SPB_INFO_PATCH_UPLOAD_CONFIG');
    my $upload_cmd = "$ENV{ISD_HOME}/bin/uploadcli  upload ";
    $upload_cmd .=$upload_config;
    foreach my $h_key (keys %{$params}) {
        $upload_cmd .= " --${h_key}='$params->{$h_key}'" if ($params->{$h_key} ne "");
    }
    $self->{log_fh}->print('=' x 100, "\n\n");
    
    $self->{log_fh}->print(" Uploading SPB Tracking Patch from $host_name...\n\n");
    eval{
        $self->{log_fh}->print('*' x 100, "\n\n");
        my $error_message = "";
        my $system     = new DoSystemCmd();
        $system->do_cmd_ignore_error($upload_cmd, (keep_output => 'YES', timeout => 1800));
        my (@cmd_output) = $system->get_last_do_cmd_output();
        my $result;
        foreach my $line (@cmd_output) {
            chomp($line);
            if ($line =~ /<error_message>(.*)<\/error_message>/) {
            $error_message = $1;
            }
        }
         if ($error_message) {
            # sleep and retry
            sleep(60);
            $system->do_cmd_ignore_error($upload_cmd, (keep_output => 'YES', timeout => 1800));
            (@cmd_output) = $system->get_last_do_cmd_output();
        } 
        $result = join("\n", @cmd_output);
        $tracking_aru = $& if($result =~ /(?<=aru\>)\d+(?=\<\/aru)/m);
        $self->{log_fh}->print("SPB tracking Patch Upload Status \n $result \n");
        $self->{log_fh}->print('*' x 100, "\n\n");
    };
    return $tracking_aru;

}
#
# Extracts zip file/overwrites contents into given location.
# or it can be used as customecommand self->process_cus_or_unzip_cmd({cmd=>'Pass command'});
#
sub process_cus_or_unzip_cmd{

    my ($self,$args) = @_;
    my ($src_file,$dest_loc,$cmd,$keep_output,$log_fh);
    $src_file       = $args->{'src_file'};
    $dest_loc       = $args->{'dest_loc'};
    $cmd            = $args->{'cmd'};
    $keep_output    = 'YES';
    $keep_output    = $args->{'keep_output'} if(exists($args->{'keep_output'}));
    $log_fh         = $self->{log_fh};
    my $system     = new DoSystemCmd();

    $cmd = "unzip -o $src_file -d $dest_loc" if(!$cmd);
    $log_fh->print("Executing Command from custom cmd function:\n $cmd\n keep_output $keep_output\n");

    if($keep_output eq "NO"){
        $system->do_cmd_ignore_error($cmd, (keep_output => 'NO', timeout => 1800));
    }else{
        $self->exec_retry_command
                (do_cmd_obj => $self->{system},
                    method  => 'do_cmd_ignore_error',
                    args    => [ $cmd, (keep_output => $keep_output ,
                        timeout                     => PB::Config::ssh_timeout) ]);
    }
}



1;

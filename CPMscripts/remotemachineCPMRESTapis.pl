package ARUForms::CPMRestAPIs;

#
# REST API module to contain all REST api CPM needs to provide. Rewrite rule
# in aruforms.conf so as to point the rest api url to one of the subs here.
# Common usage for methods:
# GET - safe apis, should only get values and do nothing else
# PUT - for adding new data
# POST - For updating existing data
# DELETE - For deleting existing data
#

use strict;
use warnings;
use ARUForms::ARUForm;
use ARUDB;
use ARUForms::BackportCLIReview;
use ARUForms::FastBranchSetup;
use JSON;
use     vars qw(@ISA);
use Data::Dumper;
use Log;
use DateUtils;
use XML::DOM;
use XML::LibXML;
use IPC::Open3;
use Symbol 'gensym';
use ConfigLoader 'ARUForms::Config' => "$ENV{ISD_HOME}/conf/aruforms.pl";
use constant FAST_BRANCH_DIR =>
                            $ENV{ISD_HOME}."/data/CPCT/fast_branch_setup";
use constant FMW_SEMI_ANNUAL_XML_DIR =>
                            "/net/slcnas629/export/ddr_se/apf/workarea/st_apf/FMW12cSemiAnnualXml";
@ISA = qw(ARUForms::ARUForm ARUForms::BackportCLIReview
          );


sub new {

    my $self = ARUForms::ARUForm::new("ARUForms::CPMRestAPIs");
    $self->set_authorization('anyone');

    return $self;
}

sub get_open_release
{
 my ($self, $cgi, $req) = @_;
 my $restAPI = ARUForms::CPMRestAPIs->new();

 my $series_name = URI::Escape::uri_unescape($cgi->param("series_name"));
 my $label_name = URI::Escape::uri_unescape($cgi->param("label_name"));
 my $manifest = URI::Escape::uri_unescape($cgi->param("manifest"));
 my $trk_group = URI::Escape::uri_unescape($cgi->param("tracking_group"));

my $xml_file = URI::Escape::uri_unescape($cgi->param("bugfix_xml"));
 my $timestamp = POSIX::strftime("%d-%b-%Y-%R:%S", localtime());
 $timestamp =~ s/-|://g;
 my $local_xml_file = FMW_SEMI_ANNUAL_XML_DIR."/bugfix_".$timestamp.".xml";

 my $sql = "select  acps.product_id, acps.series_id, acps.product_name, ar.release_name ".
 " from aru_Cum_patch_series acps, aru_releases ar ".
 " where acps.series_name =  '$series_name' ".
 " and ar.release_id = acps.base_release_id ";

 my @result = ARUDB::dynamic_query($sql);
 my $product_id  = $result[0]->[0];
 my $prod_series_id  = $result[0]->[1];
 my $prod_name  = $result[0]->[2];
 my $release_name  = $result[0]->[3];

 my $rel_str  = $release_name;
 $rel_str =~ s/\.//g;

 $sql = "select parameter_value ".
 " from aru_cum_patch_series_params ".
 " where series_id = $prod_series_id ".
 " and parameter_name = 'Series Branch Name' ";
 @result = ARUDB::dynamic_query($sql);
 my $series_branch_name = $result[0]->[0];

 my $product_list = "";
 my $rel_branch_list  = "";
 my $excep_product_list = "";
 my $is_xml_mandatory = 0;
 my $rel_list = "";
 eval {
       $product_list = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                                      'SEMI_ANNUAL_ENABLED_PROD_RELS');
 };

 eval {
       $excep_product_list = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                                            'SEMI_ANNUAL_EXCEPTIONAL_PROD_RELS');
 };

 eval {
       $rel_branch_list = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                                         'SEMI_ANNUAL_ENABLED_BRANCH');
 };

 my $enabled_prod_rel = 0;
 if (defined $product_list && $product_list ne "" )
 {
   my (@prod_list) = split(',',$product_list);
   foreach my $prod_abbr (@prod_list)
   {
      if ($prod_abbr =~ /$prod_name/)
      {
         my ($prod, $rel) = split(':', $prod_abbr);
         if ($rel_str >= $rel)
         {
            $enabled_prod_rel = 1;
         }
      }
   }

   if ($enabled_prod_rel == 1 &&
       defined $excep_product_list && $excep_product_list ne "" &&
       $excep_product_list =~ /$prod_name/)
   {
       my (@excep_prod_list) = split(',',$excep_product_list);
       foreach my $excep_prod_abbr (@excep_prod_list)
       {
          if ($excep_prod_abbr =~ /$prod_name/)
          {
            my ($prod, $rel) = split(':', $excep_prod_abbr);
            if ($rel =~ /$rel_str/ || $rel =~ /$release_name/)
            {
                $enabled_prod_rel = 0;
            }
          }
       }
    }

    if ($enabled_prod_rel == 1 &&
        (defined $rel_branch_list && $rel_branch_list ne "") &&
        ($rel_branch_list =~ /$prod_name/)  )
    {
       my (@prod_rel_branches) = split(',',$rel_branch_list);
       foreach my $prod_rel_branch (@prod_rel_branches)
       {
          if ($prod_rel_branch =~ /$prod_name/)
          {
             my ($prod, $branches) = split(':', $prod_rel_branch);
             my (@branch_list) = split('\|', $branches);
             foreach my $branch_str (@branch_list)
             {
               if ($series_branch_name  =~ /$branch_str/)
               {
                  $is_xml_mandatory = 1;
               }
              }
            }
         }
     }
     elsif ($enabled_prod_rel == 1)
     {
         $is_xml_mandatory = 1;
     }
 }

 my $ret_json;
 my $get_tg_bug = 1;

 if($ENV{REQUEST_METHOD} eq 'GET'){

      if ($is_xml_mandatory == 1 &&
        (! defined $xml_file || $xml_file eq ""))
    {
      $get_tg_bug = 0;
      $ret_json = <<JSON_RET;
         {

           "error": "Bugfix XML file is not provided. Its mandatory for the series $series_name "
         }
JSON_RET

    }
    if ($get_tg_bug == 1 &&  $is_xml_mandatory == 1)
    {
       my $xml_log_file = FMW_SEMI_ANNUAL_XML_DIR."/bugfix_".$timestamp.".log ";
       my $wget_cmd = "wget -o $xml_log_file  $xml_file  -O $local_xml_file ";
       my $system   = new DoSystemCmd();
       $system->set_filehandle(undef);
       $system->do_cmd($wget_cmd);
       if (! -f $local_xml_file)
       {
         $get_tg_bug = 0;
         $ret_json = <<JSON_RET;
         {

           "error": "Bugfix XML file $xml_file is not accessible"
         }
JSON_RET
       }
    }
    if ($get_tg_bug == 1)
    {
      $ret_json = $self->_getOpenTGBugJson($series_name, $label_name,
                                           $manifest, $trk_group, $prod_series_id, $local_xml_file);
    }
}
 else{
   $ret_json = <<JSON_RET;
         {

           "error": "unsupported http method"
         }
JSON_RET
}

 print STDOUT $cgi->header("Content-Type: text/json");
 print STDOUT $ret_json;

}


sub send_cgi_header {
    my($self, $req) = @_;

    my @header;
    my $CRLF = "\n";
    push(@header, "Content-Type: application/json");
    push(@header, "Access-Control-Allow-Origin: *");
    push(@header, "Access-Control-Allow-Credentials: true");
    push(@header, "Access-Control-Allow-Headers: Content-Type");

    my $header = join($CRLF,@header)."${CRLF}${CRLF}";
    $req->send_cgi_header($header);
}

sub _getOpenTGBugJson{
     my ($self,$series_name, $label_name, $manifest, $trk_group, $prod_series_id, $xml_file) = @_;
     my %op;
     my $restop = {};
     $restop->{'release'} = undef;
     my $orig_query = $series_name;
     $series_name =~s/'/''/g;
     if($series_name){
         %op = $self->_getOpenTgBug($series_name, $label_name, $manifest,
                                    $trk_group, $prod_series_id,$xml_file);

         if(%op){
                 $restop->{'release'} = {%op};
             }
         else{
             my $error = 'No open releases found';
             my ($res)= ARUDB::dynamic_query("select count(series_id)
                        from aru_cum_patch_series
                         where series_name='$series_name'");
             if($res->[0] == 0){
                 $error = "Series not found in CPM: $orig_query";
               }
            $restop->{'error'} = $error;
        }
     }
     else{
         $restop->{'error'} = 'No Series name given';
     }
     my $jsonString = encode_json($restop);

     return $jsonString;
}

sub _getOpenTgBug
{
   my ($self,$series_name,$label_name, $manifest, $trk_group, $prod_series_id, $xml_file) = @_;
   my %rel_status = (34522=>'Codeline Open',
                     34523=>'Codeline Frozen',
                     34526=>'Codeline Open Setup');
   my $status;
   my $release_version;
   my %op = ();
   my $bugfixes = "";
   my $xml_doc = "";

   if (-f $xml_file){
     my $parser = XML::LibXML->new();
     $xml_doc = $parser->parse_file($xml_file);

     for my $xml_phase ($xml_doc->findnodes('/patch-metadata-def'))
     {
        for my $child_xml_phase ($xml_phase->findnodes('./bugfix-info'))
        {
            my $bugfix = $child_xml_phase->getAttribute('bugFix');
            chomp($bugfix);
            $bugfix =~ s/^\s+|\s+$//g;
            if ($bugfixes !~ /$bugfix/)
            {
                $bugfixes .= $bugfix.",";
            }
        }
     }
     $bugfixes =~ s/,$//g;
   }

   if($series_name){

       my $sql = "select acpr.tracking_bug,acpr.status_id ,acpr.release_name,
                  acpr.release_id, ar.release_name, acps.series_id,
                  acpr.release_version
              from aru_cum_patch_series acps, aru_cum_patch_releases acpr,
                   aru_releases ar
               where acps.series_id = acpr.series_id
                           and acpr.status_id in (34522,34523,34524)
                           and acps.series_name = '$series_name'
                           and ar.release_id = acps.base_release_id
                order by acpr.status_id asc";

       my $tgbug;
       my $release_id;
       my ($result) = ARUDB::dynamic_query($sql);

       #
       # Bug 27402580 - to allow testing bundle patches with
       # patch_level via cumulative/upgrade patching pipeline
       # If series name passed to the REST API is not
       # found, check for base bug in BUGDB
       #
       unless ($result)
       {
           if ($series_name !~ /\.0$/)
           {
                $sql = "select base_bug, 'Codeline Open', subject, version_id
                        from   bugdb_rpthead_v brv, aru_backport_requests abr
                        where  upper(brv.subject) = upper('$series_name')
                        and    brv.generic_or_port_specific = 'G'
                        and    brv.status not in (53, 55, 59)
                        and    abr.base_bug = brv.rptno
                        and    abr.request_type=45051
                        and    abr.status_id = 45002
                        and    rownum = 1";
           }

           ($result) = ARUDB::dynamic_query($sql);
           return unless ($result);
       }

       if($result){
          my $series_id = $result->[5];
          $release_version = $result->[6];
           my $is_cont_dated_rel = ARUDB::exec_sf
               ("aru_cumulative_request.get_series_parameter_value",
                $series_id, "Continuous Dated Release");
           $is_cont_dated_rel ||= 'NO';

           if (uc($is_cont_dated_rel) eq 'YES')
           {
               if ($release_version && ($label_name || $manifest))
               {
                   if ($manifest)
                   {
                       $manifest =~ s/:pom\s*$//;
                       $manifest =~ s/(-manifest):(\d)/$1-$2/;
                       $manifest =~ s/(\d)-(\d)/$1_$2/;
                       $label_name = $manifest;
                   }
                   my ($old_tgbug, $new_tgbug);
                   my @params = (
                             { name => "pv_label_name",
                               data => $label_name },
                             { name => "pv_release_version",
                               data => $release_version },
                             { name => "pv_series_name",
                               data => $series_name },
                             { name => "pb_execption",
                               data => 0,
                               type => 'boolean' },
                             { name => "pno_old_tracking_bug",
                               data => \$old_tgbug },
                             { name => "pno_new_tracking_bug",
                               data => \$new_tgbug }
                                );

                   my ($error) = ARUDB::exec_sp
                       ("aru_cumulative_request.create_label_tracking_bug",
                        @params);
                   $tgbug = $new_tgbug;
               }
               # If label_name is not passed and manifest is not
               # defined, result is empty for series enabled for stream release
               #
               elsif (!defined($manifest))
               {
                   return %op;
               }

           }
           else
           {
               $tgbug = $result->[0];
           }
           $status = $rel_status{$result->[1]};
           $release_id =  $result->[3];
           $op{'status'} = $status;
           $op{'trackingBug'} = $tgbug;
           $op{'releaseName'} = $result->[2];

           if (-f $xml_file)
           {
             my $ci_fixes = $self->create_placeholder_ci($bugfixes, $series_name, $prod_series_id, $release_id);
             if (defined $xml_doc && $xml_doc ne "" && $xml_doc->toString() ne "")
             {
                 my @params = (
                     {name => 'p_rptno' ,
                      data => $tgbug
                     },
                     {name => 'p_text' ,
                      data => $xml_doc->toString()
                     }
                     );
                my $error = ARUDB::exec_sp('aru_backport_util.add_bug_text',
                            @params);
                @params = (
                     {name => 'p_rptno' ,
                      data => $tgbug
                     },
                     {name => 'p_text' ,
                      data => "APF filed CIs in the previous run $self->{prev_filed_cis} \n".
                      "CI filed in the current run: $ci_fixes"
                     }
                     );
                $error = ARUDB::exec_sp('aru_backport_util.add_bug_text',
                            @params);

              }
           }
           # get the blr bug for the tracking bug
           $op{'BLRBug'} = $self->_getBLRBug($tgbug,$release_id);

          #
          # Set tracking group (if defined on bundle tracking bug
          #
          if ($tgbug && $trk_group)
          {
              my ($trk_grp_name, $trk_attr, $trk_value) =
                  ($trk_group =~ /^([^-]*)\s+-\s*([^-\s]*)\s*-\s*(.*)$/);
              my ($error_msg) =
                  ARUDB::exec_sf("pbuild.create_tracking_grp_for_bug",
                                 $tgbug, $trk_grp_name, $trk_value,
                                 $trk_attr, '%');
          }

       }
   }

   return %op;

}

sub _getBLRBug
{   # Arg - base bug number
    #     - version_id
    my($self,$bug,$version_id) = @_;
    my $sql = "select backport_bug
               from aru_backport_requests
               where base_bug=$bug
               and version_id=$version_id
               and request_type=45051
               and status_id = 45002";
    my $bp_bug = ARUDB::dynamic_query($sql)->[0]->[0];
    if(!$bp_bug){
        #
        # No BLR found in backport requests, check if bugdb BLR exists,
        # possibly filed from APF or manually.
        #
        my $series_id = ARUDB::dynamic_query("select series_id from
                         aru_cum_patch_releases
                         where release_id=$version_id")->[0]->[0];
        my $base_rel = ARUDB::exec_sf(
                              'aru_cumulative_request.get_base_release',
                               $series_id);
        $sql = "select distinct rptno
                from  bugdb_rpthead_v
                where base_rptno = $bug
                and   generic_or_port_specific = 'B'
                and   status not in (53, 55, 59)
                and   utility_version = '$base_rel'";
        $bp_bug = ARUDB::dynamic_query($sql)->[0]->[0];
        #
        # If still no BLR found, file it. Default to 226 as this API
        # is used for FMW 12c only. Platform is auto-switched to generic
        # during patch gen. as needed
        #
        if (!$bp_bug)
        {
            my @params = (
                   { name => "pn_tracking_bug",
                     data => $bug },
                   { name => "p_release_id",
                     data => $version_id },
                   { name => "pv_pf_list",
                     data => '226' }
                      );
            my ($error) = ARUDB::exec_sp
                ("aru_cumulative_request.file_pse_tracking_bug", @params);
            $sql = "select backport_bug
                    from aru_backport_requests
                    where base_bug=$bug
                    and version_id=$version_id
                    and request_type=45051
                    and status_id = 45002";
            $bp_bug = ARUDB::dynamic_query($sql)->[0]->[0];
        }
    }
    return $bp_bug;

}
sub get_patch_content{
    my($self,$cgi,$req) = @_;
    my $rel_version = URI::Escape::uri_unescape($cgi->param("release_version"));
    my $patch_number = URI::Escape::uri_unescape($cgi->param("patch_number"));
    my $response;
    my $error;
    my $fixed_bugs='{}';
    my $ret_json;
    my %op=();
   if($ENV{REQUEST_METHOD} ne 'GET'){
         $response = 'Failed';
         $error    = 'unsupported http method';
         goto LABEL;
   }
   if(!$rel_version && !$patch_number){
        $response = 'Failed';
        $error    = 'CPM release version or patch number is needed!';
        goto LABEL;
   }
   if($patch_number && $patch_number !~ /^\d+$/){
       $response = 'Failed';
       $error    = 'Patch number should be numeric!';
       goto LABEL;
   }
   if($rel_version){
    eval{
     my $sql = "select release_id,series_id
                from   aru_cum_patch_releases
                where  release_version ='".$rel_version."'";
     my @result  = ARUDB::dynamic_query($sql);
     my $release_id = $result[0]->[0];
     my $series_id  = $result[0]->[1];
     if(!$release_id){
        $response = 'Failed';
        $error    = 'Invalid CPM release version!';
        goto LABEL;

     }
       $sql = "select brv.rptno,brv.subject
                 from  aru_cum_codeline_requests cr,
                       aru_cum_patch_releases r,
                       bugdb_rpthead_v brv
                 where cr.release_id = r.release_id
                 and   cr.base_bug = brv.rptno
                 and   r.status_id in (34523,34524)
                 and   r.series_id = $series_id
                 and   cr.status_id in (34588,96302,34597,34583,96371)
                 union
                 select brv.rptno,brv.subject
                 from  aru_cum_codeline_requests cr,
                       aru_cum_patch_releases r,
                       bugdb_rpthead_v brv
                 where cr.release_id = r.release_id
                 and   cr.base_bug = brv.rptno
                 and   r.release_id = $release_id
                 and   r.series_id = $series_id
                 and   cr.status_id in (34588,96302,34597,34583,96371)
                ";
        @result  = ARUDB::dynamic_query($sql);
        foreach my $rec (@result){
             my $bug = $rec->[0];
             $op{$bug} = $rec->[1];
        }
          if(%op){
              $response = 'Success';
              $error    = '';
              $fixed_bugs = encode_json \%op;
              goto LABEL;
          }else{
             $response = 'Failed';
             $error    = 'No Fixed Bugs';
             goto LABEL;

          }
      1;
     }or
     do{
         $response = 'Failed';
         $error    = 'Invalid CPM release version!';
         goto LABEL;
      };


   }elsif($patch_number){
       my $sql = "select abbr.related_bug_number as bug,brv.subject
                  from   aru_bugfix_bug_relationships abbr,
                         isd_bugdb_bugs ibb,
                         bugdb_rpthead_v brv
                  where  abbr.related_bug_number = ibb.bug_number and
                         abbr.relation_type in (609,610,613 )and
                         abbr.bugfix_id = (select bugfix_id
                                           from ARU_BUGFIXES
                                           where BUGFIX_RPTNO=$patch_number
                                           and rownum=1)
                         and  abbr.related_bug_number = brv.rptno";

       my @result = ARUDB::dynamic_query($sql);
        foreach my $rec (@result){
             my $bug = $rec->[0];
             $op{$bug} = $rec->[1];
        }
          if(%op){
              $response = 'Success';
              $error    = '';
              $fixed_bugs = encode_json \%op;
              goto LABEL;
          }else{
             $response = 'Failed';
             $error    = 'No Fixed Bugs';
             goto LABEL;

          }


   }

LABEL:
$ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "fixed_bugs":$fixed_bugs

         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;


}

#
# Return the fixed bugs for given CPM series
#
sub get_fixed_bugs
{
    my ($self, $cgi, $req) = @_;
    my $restAPI = ARUForms::CPMRestAPIs->new();

    my $series_name = URI::Escape::uri_unescape($cgi->param("series_name"));
    my $date_ts = URI::Escape::uri_unescape($cgi->param("merge_time"));
    my $ci_content_type =
           URI::Escape::uri_unescape($cgi->param("content_type"));
    my $ret_json;

    if($ENV{REQUEST_METHOD} eq 'GET'){

        $ret_json = $self->_getFixedBugsJson($series_name, $date_ts,
                                             $ci_content_type);
    }
    else
    {
        $ret_json = <<JSON_RET;
        {

           "error": "unsupported http method"
        }
JSON_RET
    }
    print STDOUT $cgi->header("Content-Type: text/json");
    print STDOUT $ret_json;
}


sub _getFixedBugsJson
{
    my ($self, $series_name, $date_ts, $ci_content_type) = @_;

    my $op = [];
    my $restop = {};
    my $orig_query = $series_name;
    $series_name =~ s/'/''/g;
    my $iso_dts = DateUtils::to_iso8601($date_ts);

    if($series_name && ($date_ts || $ci_content_type))
    {
       #
       # ! HACK! - allow test release name for patch_level bundle testing
       #
       $series_name =~ s/\.\d+$/\.0/ unless ($series_name =~ /\.0$/);

       if ($iso_dts || $ci_content_type)
       {

       $op = $self->_getFixedBugs($series_name, $iso_dts, $ci_content_type);
       if(@$op)
       {
          unless ($ci_content_type)
	  {
             $restop->{'error'} = "Merge time not provided" unless ($date_ts);
             $restop->{'error'} = "Invalid merge time : $date_ts"
                      if ($date_ts && ! $iso_dts);
          }
          $iso_dts ||= 'Current time';
          $restop->{'fixedbugs'} = $op;
       }
       else
       {
          my $error = 'No fixed bugs found';
          my ($res)= ARUDB::dynamic_query("select count(series_id)
                                          from aru_cum_patch_series
                                          where series_name='$series_name'");
          if($res->[0] == 0)
          {
             $error = "Series not found in CPM: $orig_query";
          }
          $restop->{'error'} = $error;
        }

        }
        else
        {
          if (! $iso_dts && !$ci_content_type)
	  {
           $restop->{'error'} = "Merge time not valid : $date_ts.";
           $restop->{'error'} .= " Valid formats:  ".
                               "[2018-02-09 11:55:30]  ".
                               "[Fri Feb 9 11:55:30 2018]  ".
                               "[Friday, 09-Feb-2018 11:55:30 GMT]  ".
                               "[Fri, 09 Feb 2018 11:55:30 GMT]";
         }
        }
    }
    else
    {
        unless ($series_name)
        {
            $restop->{'error'} = 'No Series name given';
        }
        unless ($date_ts || $ci_content_type)
        {
            $restop->{'error'} = 'No merge time given';
        }
    }
    my $jsonString = encode_json($restop);

    return $jsonString;
}

sub _getFixedBugs
{
    my ($self, $series_name, $date_ts, $ci_content_type) = @_;

    my %op = ();

    if ($series_name)
    {
       my ($where_1, $bind_index_1, $bind_vals_ref_1);
       my @ci_status_ids;
       if (lc($ci_content_type) eq 'cumulative')
       {
           @ci_status_ids = qw[34583 34588 34597 96302 96371];
       }
       elsif (lc($ci_content_type) eq 'delta')
       {
              @ci_status_ids = qw[34588];
       }
       my %where_1 = ("accr.status_id" => \@ci_status_ids);
       ($where_1, $bind_index_1, $bind_vals_ref_1) =
                OraDB::generate_where(\%where_1); 
       my $sql = "select distinct basebug, status, branch, txn
                  from
                   (select accr.base_bug basebug, ascs.description status,
		           nvl(acra1.attribute_value, 'NA') branch,
			   nvl(acra2.attribute_value, 'NA') txn
                    from   aru_cum_codeline_requests accr,
                    aru_cum_patch_series acps, aru_cum_patch_releases acpr,
                    aru_cum_codeline_req_attrs acra,
		    aru_cum_codeline_req_attrs acra1,
		    aru_cum_codeline_req_attrs acra2,
		    aru_status_codes ascs ";
       $sql .= "where $where_1 ";
       $sql .= "and  upper(acps.series_name) = upper('$series_name')
                and    acpr.series_id = acps.series_id
                and    acpr.series_id = accr.series_id
		and    ascs.status_id = accr.status_id
                and    acra.codeline_request_id = accr.codeline_request_id
		and    acra1.codeline_request_id = accr.codeline_request_id
                and    acra2.codeline_request_id = accr.codeline_request_id
		and    acra1.attribute_name = 'ADE Merged Branch'
		and    acra2.attribute_name = 'ADE Transaction Name' 
                     and    ((acra.attribute_name = 'ADE Merged Timestamp' and
                             acra.attribute_value is not null and
                             to_date(acra.attribute_value,
                                    'DD-MON-YYYY HH24:MI:SS') <
                                nvl(to_date('$date_ts',
                                      'YYYY-MM-DD HH24:MI:SS'), sysdate)) or
                            (acra.attribute_name = 'ADE Merged Timestamp' and
                             acra.attribute_value is null and
                             accr.last_updated_date <
                                  nvl(to_date('$date_ts',
                                        'YYYY-MM-DD HH24:MI:SS'), sysdate)) or
                             (not exists
                                (select 1
                                 from aru_cum_codeline_req_attrs acra1
                                 where acra1.codeline_request_id =
                                               accr.codeline_request_id
                                 and acra1.attribute_name =
                                               'ADE Merged Timestamp') and
                                 accr.last_updated_date <
                                     nvl(to_date('$date_ts',
                                          'YYYY-MM-DD HH24:MI:SS'), sysdate)))
                    and    acpr.release_id = accr.release_id
                    and    acpr.tracking_bug is not null
                    and    acpr.status_id in (34522,34523, 34524)
                    order by accr.codeline_request_id asc)";

       my @result = ARUDB::dynamic_query($sql, 0, @$bind_vals_ref_1);
       my @fixed_bugs_list;
       foreach my $row (@result)
       {
          my ($bug, $status, $branch, $txn) = @$row;
	   my %fixed_bug_details;
	   $fixed_bug_details{'bug'} = $bug;
	   $fixed_bug_details{'status'} = $status;
	   $fixed_bug_details{'branch'} = $branch;
	   $fixed_bug_details{'transaction'} = $txn;

           my ($return_code, $return_msg, $abstr, $category,
               $gp_flag,  $cs_priority, $portid, $product_id);
           eval
           {
             ($return_code, $return_msg, $abstr, $category,
              $gp_flag,  $cs_priority, $portid, $product_id)
                 = BUGDB::get_bug_info($bug);
           };
           $abstr ||= "Fix for Bug $bug";
	   if ($ci_content_type)
	   {
	       $product_id ||= 'NA';
  	       $category ||= 'NA';
	       $fixed_bug_details{'product_id'} = $product_id;
	       $fixed_bug_details{'component'} = $category;
	   }
	   push(@fixed_bugs_list, \%fixed_bug_details);
       }
       return \@fixed_bugs_list;
   }
}


sub release_sys_patch{
  my($self,$cgi,$req) = @_;
  my $ret_json     = '';
  my $response;
  my $error;
  my $release_id =  $cgi->param('release_id');
  my $user_id    =  $cgi->param('user_id');
  use ARUForms::BackportCLIRelease;
  $response = 'Success';
  $error    = '';
  if(!$release_id || $release_id !~ /^\d+$/ ){
        $response = 'Failed';
        $error    = 'Invalid Release Id';
        goto LABEL;
  }
 if(!$user_id || $user_id !~ /^\d+$/ ){
        $response = 'Failed';
        $error    = 'Invalid User Id';
        goto LABEL;
  }

$req->pool->cleanup_register(
            sub {
  ARUForms::BackportCLIRelease->release_system_patch($release_id,$user_id);
      });

LABEL:
$ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error"
         }
JSON_RET

    #print STDOUT $cgi->header("Content-Type: text/json");
    $self->send_cgi_header($req);
    print STDOUT $ret_json;
}

sub create_release_candidate
{

    my ($self, $cgi, $req) = @_;

    my $json_decoded = '';
    my $release_id = '';
    my $release_name = '';
    my $raise_error  = '';
    my $ret_json     = '';
    my $version = '';
    my $error = '';
    #my $in_data = $cgi->param('POSTDATA');
    my $obj = ARUForms::BackportCLIReview->new();
    #print STDERR "INPUT_STRING\n",Dumper($in_data);
#    eval
#    {
#        $json_decoded = decode_json($in_data);
#        1;
#    } or
#    do
#    {
#        $raise_error = 'Error:Not a valid JSON input.' ;
#        $ret_json = <<JSON_RET;
#        {
#          "error": "$raise_error"
#        }
#JSON_RET
#    };

    #if(!$raise_error)
    #{
        my $tracking_bug = $cgi->param('tracking_bug');
        #my $tracking_bug    = $json_deco->{tracking_bug};
        #my $user_name = $json_decoded->{user};
        my $user_name = $cgi->param('user');
        my $user_id;
        unless($user_name) {
            $raise_error = "User name must be provided to invoke this API";
            goto LABEL;
        }
        if($user_name) {
            $user_id = ARUDB::exec_sf('aru_user.find_user_id',$user_name);
        }
        unless($user_id) {
            $raise_error = "Please provide a valid user name";
            goto LABEL;
        }
        if ($tracking_bug =~ /^\d+$/)
        {
            my $query =
            "
            select  acpr.release_id,acpr.release_name,
                    acps.product_id,acps.series_id
            from    aru_cum_patch_releases acpr,
                    aru_cum_patch_series acps
            where acpr.tracking_bug = $tracking_bug
            and acpr.series_id = acps.series_id
           ";
            my ($result)         = ARUDB::dynamic_query($query);
            my $product_id;
            my $series_id;
            ($release_id,$release_name,$product_id,$series_id) = @$result if($result);
            if($release_id && $product_id) {
            my $can_access = $obj->has_admin_responsibility($user_id,$product_id);
            my $has_qa_resp = $self->has_QA_responsibility($user_id,$series_id);
            unless($can_access || $has_qa_resp) {
                $raise_error = "$user_name does not have access to create Release Candidate";
                $release_name = '';
                goto LABEL;
            }
                $raise_error = '';
                goto LABEL;
            }
         }
         else {
            $raise_error = 'Please provide a valid tracking bug.';
            goto LABEL;
         }
         unless($release_id)
            {
            my ($series_name, $release);
            ARUDB::exec_sp('aru_cumulative_request.get_tracking_bug_details',
                   $tracking_bug, \$series_name, \$release
            );

            my ($series_id) =  ARUDB::exec_sf('aru_cumulative_request.get_series_id',
                                      $series_name);

            my $prod_query =
            "
            select
                    product_id
            from    aru_cum_patch_series acps
            where series_id = $series_id
           ";
            my ($prod_res)         = ARUDB::dynamic_query($prod_query);
            my $prod_id;
            ($prod_id) = @$prod_res if($prod_res);
            my $can_access = $obj->has_admin_responsibility($user_id,$prod_id);
            my $has_qa_resp = $self->has_QA_responsibility($user_id,$series_id);
            unless($can_access || $has_qa_resp) {
                $raise_error = "$user_name does not have access to create Release Candidate";
                $release_name = '';
                goto LABEL;
            }

                        my $query =
           "select parameter_name,
                    regexp_substr
                    (parameter_name,
                    '(\\d{6,})(\\.)?(\\d{4,})?\$'
                    ),acps.patch_type
           from
                aru_cum_patch_release_params acprp,
                aru_cum_patch_releases acpr,
                aru_cum_patch_series acps
           where
                parameter_type = 34593
                and to_number(acprp.parameter_value) = $tracking_bug
                and acpr.release_id = acprp.release_id
                and acpr.series_id = acps.series_id
                and acps.series_id = $series_id
                and rownum < 2
           ";
           my ($result) = ARUDB::dynamic_query($query);
           my ($bp_label,$build_time,$patch_type_code)   = @$result if($result);
           if(!$bp_label) {
                $raise_error = "Tracking Bug is not associated with any label in CPM";
                $release_name = '';
                goto LABEL;
           }
           else {
           my $ver_query =
                    "select
                    aru_backport_util.ignore_fifth_segment(
                    aru_backport_util.pad_version(
                    ar.release_name)
                    )
                    from
                        aru_releases ar,
                        aru_cum_patch_series acps
                    where
                        ar.release_id = acps.base_release_id
                    and acps.series_id=$series_id
           ";
           my ($base_ver_res) = ARUDB::dynamic_query($ver_query);
           my ($series_base_version) = @$base_ver_res if($base_ver_res);
           my $build_date;
           my $support_8_digit;
           my $support_8_digit_patch;
              ($support_8_digit) = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                                 'SUPPORT_8_DIGIT_VERSION');
              ($support_8_digit_patch) = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                                 'SUPPORT_8_DIGIT_PATCH_TYPE');


           if($build_time =~ /(\d+)\.?(\d+)?/) {
              $build_date = $1;
              my $temp_build_date = substr($1.$2,0,8);
              if($patch_type_code && $support_8_digit eq 'Y'){
                if($patch_type_code =~ /$support_8_digit_patch/){
                 $build_date = $temp_build_date;
                }
              }

           }
           if($build_date && $series_base_version) {
                my $rel_ver = $series_base_version .".".$build_date;
                $version = $rel_ver;
                $version = $self->get_release_version($series_base_version,$series_id,$build_date);
           }
           my $release_status = 34529;

        my @params = ({name => "pv_series_name",
                      data => $series_name},
                     {name => "pv_release_version",
                      data => $version},
                     {name => "pn_status_id",
                      data => $release_status},
                     {name => "pn_user_id",
                      data => $user_id},
                     {name => "pno_release_id",
                      data => \$release_id});

        $error = ARUDB::exec_sp('aru_cumulative_request.create_release',
                               @params);

        if($error) {
            $raise_error = "Error while creating release candidate:$error";
            goto LABEL;
        }
        if($release_id) {
            my $rel_query =
            "
            select  release_name
            from    aru_cum_patch_releases
            where release_id = $release_id
           ";
            my ($res) = ARUDB::dynamic_query($rel_query);
            ($release_name) = $res->[0] if($result);
         ARUDB::exec_sp(
            'aru_cumulative_request.update_cum_patch_releases',
            $release_id,
            'tracking_bug',
            $tracking_bug,
            $user_id
            );
       use ARUForms::BackportCLIRelease;
       ARUForms::BackportCLIRelease->add_cumulative_content_link($release_id,$tracking_bug);
        my @param = ({name => "pn_release_id",
                    data => $release_id},
                   {name => "pv_parameter_name",
                    data => $bp_label},
                   {name => "pn_parameter_type",
                    data =>  34593},
                   {name => "pv_parameter_value" ,
                    data => $tracking_bug});

        my $err = ARUDB::exec_sp(
                            'aru_cumulative_request.add_release_parameters',
                            @param);
        }
        else {
            $release_name = '';
            goto LABEL;
        }
        }
        }
    #}
LABEL:
$ret_json = <<JSON_RET;
         {
           "release_name": "$release_name",
           "error": "$raise_error"
         }
JSON_RET

    #print STDOUT $cgi->header("Content-Type: text/json");
    $self->send_cgi_header($req);
    print STDOUT $ret_json;
}
#
# Release a release candidate
#

sub release_tracking_bug
{

    my ($self, $cgi, $req) = @_;

    my $json_decoded = '';
    my $raise_error  = '';
    my $ret_json     = '';
    my $error = '';
    my $tracking_bug = $cgi->param('tracking_bug');
    my $release_version = $cgi->param('release_version');
    my $user_name = $cgi->param('user');
    my $response = '';
    unless($tracking_bug) {
        $error = "Tracking bug must be provided.";
        $response = "";
        goto LABEL;
    }
    unless($release_version) {
        $error = "Release version must be provided.";
        $response = "";
        goto LABEL;
    }
    unless($user_name) {
        $error = "Username must be provided.";
        $response = "";
        goto LABEL;
    }
    my @params = ({name => "pn_tracking_bug",
                      data => $tracking_bug},
                     {name => "pv_release_version",
                      data => $release_version},
                     {name => "pv_user_name",
                      data => $user_name},
                     {name => "pvo_error",
                      data => \$raise_error});

        my $api_error = ARUDB::exec_sp('aru_backport_external.release_tracking_bug',
                               @params);
    if($raise_error) {
        $error = $raise_error;
        $response = "";
        goto LABEL;
    }
    if($api_error) {
        $error = $api_error;
        $response = "";
        goto LABEL;
    }
    if(!$raise_error && !$api_error) {
        $error = "";
        $response = "CPM Release was moved to Released.";
        goto LABEL;
    }

LABEL:
$ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error"
         }
JSON_RET

   # print STDOUT $cgi->header("Content-Type: text/json");
    $self->send_cgi_header($req);
    print STDOUT $ret_json;
}
sub update_bug_tag{
  my($self,$cgi,$req) = @_;
  my $tag = $cgi->param('bug_tag');
  my $delta_requests = $cgi->param('current_requests');
  my $old_requests   = $cgi->param('old_requests');
  my $error;
  my $response;
  my $bugs_tags;
  my $json_decoded = '';
   if($ENV{REQUEST_METHOD} eq 'POST'){
      if($cgi->param('POSTDATA')){
        my $postdata = $cgi->param('POSTDATA');
        eval{
           $json_decoded = decode_json($postdata);
           1;
        }or
        do{
            $error = 'Not a valid JSON input.';
            $response = 'Failed';
            $bugs_tags='';
            goto LABEL;
        };
           $tag = $json_decoded->{'bug_tag'};
           $delta_requests = $json_decoded->{'current_requests'};
           $old_requests   = $json_decoded->{'old_requests'};
      }

   }
  if(!$tag){
    $error = 'In valid/null tag provided';
    $response = 'Failed';
    $bugs_tags='';
    goto LABEL;
  }elsif(!$delta_requests || $delta_requests !~ /\d+(,)*/ig){
    $error = 'In valid/null request_ids provided';
    $response = 'Failed';
    $bugs_tags='';
    goto LABEL;

  }
  my @request_ids = split(',',$delta_requests);
     @request_ids = grep{ $_ ne ''} @request_ids;
  $delta_requests = join(',',@request_ids);
  my @old_requests = split(',',$old_requests);
     @old_requests = grep{ $_ ne ''} @old_requests;
  $old_requests   = join(',',@old_requests);
  my $sql = "select distinct (abbr.related_bug_number)
                  from aru_bugfix_bug_relationships abbr,
                       aru_bugfix_relationships abr,
                       aru_bugfix_requests ab
                  where abbr.bugfix_id = abr.related_bugfix_id
                  and abr.relation_type = 696
                  and abbr.relation_type in (609,610)
                  and ab.bugfix_id = abr.bugfix_id
                  and ab.bugfix_id in (
                      select distinct bugfix_id
                      from   aru_cum_codeline_requests
                      where  codeline_request_id in ($delta_requests)
                  ) union
            select distinct (abbr.related_bug_number)
            from aru_bugfix_bug_relationships abbr
            where abbr.bugfix_id in (
                   select distinct bugfix_id
                   from aru_cum_codeline_requests
                   where codeline_request_id in ($delta_requests)
                   )
                   and abbr.relation_type in (609,610)";
    if($old_requests){
       $sql = $sql .' minus ';
       $sql = $sql." (select distinct (abbr.related_bug_number)
                  from aru_bugfix_bug_relationships abbr,
                       aru_bugfix_relationships abr,
                       aru_bugfix_requests ab
                  where abbr.bugfix_id = abr.related_bugfix_id
                  and abr.relation_type = 696
                  and abbr.relation_type in (609,610)
                  and ab.bugfix_id = abr.bugfix_id
                  and ab.bugfix_id in (
                      select distinct bugfix_id
                      from   aru_cum_codeline_requests
                      where  codeline_request_id in ($old_requests)
                  ) union
            select distinct (abbr.related_bug_number)
            from aru_bugfix_bug_relationships abbr
            where abbr.bugfix_id in (
                   select distinct bugfix_id
                   from aru_cum_codeline_requests
                   where codeline_request_id in ($old_requests)
                   )
                   and abbr.relation_type in (609,610))";

    }

   my @updated_bugs;
   if($delta_requests){
           my @results = ARUDB::dynamic_query($sql);
         if(@results){
           $self->remove_bug_tag($cgi,$tag,$delta_requests,$old_requests,$sql);
          }

           for my $row (@results){
             my $bug = $row->[0];
             my $bug_tags =  ARUDB::exec_sf('aru.bugdb.query_bug_tag',$bug);
             if($bug_tags =~ m/[\s*|,]?$tag[\s*|,]?/ig){
               next;
             }else{
                 my $error = ARUDB::exec_sp('aru_cumulative_request.update_eta_tag',$bug,$tag,1);
                 if(!$error){
                    push(@updated_bugs,$bug);
                 }
             }

           }


 if(scalar @updated_bugs){
    $error = '';
    $response = 'Success';
    $bugs_tags= join(',',@updated_bugs);
   }else{
    $error = '';
    $response = 'Success';
    $bugs_tags= 'nothing to update';

   }
 }

LABEL:
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "bugs_updated" : "$bugs_tags"
         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;

}

sub get_release_info{
 my ($self, $cgi, $req) = @_;
 my $tracking_bug = $cgi->param('tracking_bug');
 my $release_id;
 my $release_name;
 my $release_version;
 my $series_id;
 my $status_id;
 my $release_label;
 my $aru_release_id;
 my $response;
 my $error;

  if ($tracking_bug =~ /^\d+$/){

   my @params = ({name => "pn_tracking_bug",
                      data => $tracking_bug},
                     {name => "pno_release_id",
                      data => \$release_id},
                     {name => "pv_release_name",
                      data => \$release_name},
                     {name => "pv_release_version",
                      data => \$release_version},
                     {name => "pn_series_id",
                      data => \$series_id},
                     {name => "pn_status_id",
                      data => \$status_id
                     },
                     {name => "pv_release_label",
                      data => \$release_label
                     },
                     {name => "pn_aru_release_id",
                      data => \$aru_release_id
                     });

        $error = ARUDB::exec_sp('aru_cumulative_request.get_release_info',
                               @params);
         $response = 'Success';
         if($error){
               $response = 'Failed';
           }


  }else{
    $error = 'Please provide valid tracking bug';
    $response = 'Failed';
  }

  goto LABEL;


LABEL:
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "cpm_release_id" : "$release_id",
           "cpm_release_name": "$release_name",
           "cpm_release_version":"$release_version",
           "cpm_series_id" :"$series_id",
           "cpm_release_status":"$status_id",
           "release_label":"$release_label",
           "aru_release_id":"$aru_release_id"

         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;


}

sub get_prev_cpm_release{
  my ($self, $cgi, $req) = @_;
  my $tracking_bug = $cgi->param('tracking_bug');
  my $platform_id  = $cgi->param('platform_id');
  my $mode         = $cgi->param('patch_mode');
  my $response;
  my $error;
  my $prev_cpm_release;
  my $prev_tracking_bug;

   if($mode !~ /CD|NON_CD/gi){
     $error = 'patch_mode value can be CD or NON_CD only.';
     $response = 'Failed';
      goto LABEL;
   }
  if ($tracking_bug !~ /^\d+$/ || $platform_id  !~ /^\d+$/){
      $error = 'tracking_bug and platform_id should be valid numeric values.';
      $response = 'Failed';
      goto LABEL;
   }
  my @params = ({name => "pn_tracking_bug",
                      data => $tracking_bug},
                     {name => "pn_platform_id",
                      data => $platform_id},
                     {name => "pv_patch_mode",
                      data => uc($mode)},
                     {name => "pvo_prev_cpm_release",
                      data => \$prev_cpm_release},
                     {name => "pno_prev_tracking_bug",
                      data => \$prev_tracking_bug});

        $error = ARUDB::exec_sp('aru_cumulative_request.get_prev_cpm_release',
                               @params);
        $response = 'Success';
       if($error){
         $response = 'Failed';
       }

      goto LABEL;
LABEL:
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "previous_cpm_release" : "$prev_cpm_release",
           "previous_tracking_bug": "$prev_tracking_bug"
         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;

}
sub get_previous_patches{
  my ($self, $cgi, $req) = @_;
  my $tracking_bug = $cgi->param('tracking_bug');
  my $platform_id  = $cgi->param('platform_id');
  my $mode = 'NON_CD';
  my $response;
  my $error;
  my $prev_cpm_release;
  my $prev_tracking_bug;
  my $prev_patches = '{}';
  my %op=();
  use Tie::IxHash;
     if($ENV{REQUEST_METHOD} ne 'GET'){
         $error    = 'unsupported http method';
         $response = 'Failed';
         goto LABEL;
     }


  if ($tracking_bug !~ /^\d+$/ || $platform_id  !~ /^\d+$/){
      $error = 'tracking_bug and platform_id should be valid numeric values.';
      $response = 'Failed';
      goto LABEL;
  }
  my ($cpm_rel_id, $cpct_rel_name, $rel_ver, $aru_rel_id);
  my ($cpm_series_id, $series_status, $cpm_rel_label);
  eval{
           ARUDB::exec_sp('aru_cumulative_request.get_release_info',
                   $tracking_bug,
                   \$cpm_rel_id, \$cpct_rel_name, \$rel_ver,
                   \$cpm_series_id, \$series_status, \$cpm_rel_label,
                   \$aru_rel_id);
        };
  if(!$cpm_rel_id){
      $error = 'No CPM Release Found associated to give patch:'.$tracking_bug;
      $response = 'Failed';
      goto LABEL;
   }

 my $stream_release_id  = ARUDB::exec_sf('aru_cumulative_request.get_stream_release_id',$cpm_series_id);
   if($stream_release_id == $cpm_rel_id){
     my @params = ({name => "pn_tracking_bug",
                      data => $tracking_bug},
                     {name => "pn_platform_id",
                      data => $platform_id},
                     {name => "pv_patch_mode",
                      data => uc($mode)},
                     {name => "pvo_prev_cpm_release",
                      data => \$prev_cpm_release},
                     {name => "pno_prev_tracking_bug",
                      data => \$prev_tracking_bug});

        $error = ARUDB::exec_sp('aru_cumulative_request.get_prev_cpm_release',
                               @params);
    if(!$error && $prev_tracking_bug){
       $cpm_rel_id = ARUDB::exec_sf('aru_cumulative_request.get_cpm_release_id',$prev_tracking_bug);
    }

   }

    my $sql = "select product_name,base_release_id,patch_type
           from   aru_cum_patch_series
           where  series_id = $cpm_series_id";

    my @result = ARUDB::dynamic_query($sql);
    my $series_prod       = $result[0]->[0];
    my @series_prods      = split('\s+',$series_prod);
    my $ser_starts_with   = $series_prods[0];
    my $base_release_id   = $result[0]->[1];
    my $patch_type        = $result[0]->[2];
    my $criteria          = '<';
    my $criteriaForRURInput ='';
    my $where = "";
      if($patch_type==96022){
         $criteria  = '<=';
         $criteriaForRURInput = " and to_number(regexp_substr(acpr2.release_version,'\\d{1,}',1,2)) <=
                to_number(regexp_substr(acpr1.release_version,'\\d{1,}',1,2)) "
       }

    my $main_criteria ="select case
                          when (regexp_substr(acpr2.release_version,'RUR\$',1,1,'i') = 'RUR'
                               and (to_number(regexp_substr(acpr2.release_version,'\\d{1,}',1,2))+
                                    to_number(regexp_substr(acpr2.release_version,'\\d{1,}',1,3))) <=
                                   (to_number(regexp_substr(acpr1.release_version,'\\d{1,}',1,2))+
                                    to_number(regexp_substr(acpr1.release_version,'\\d{1,}',1,3)))
                                    $criteriaForRURInput
                              ) then acpr2.release_version
                          when (regexp_substr(acpr2.release_version,'RU\$',1,1,'i') = 'RU'
                                and to_number(regexp_substr(acpr2.release_version,'\\d{1,}',1,2)) $criteria
                                    to_number(regexp_substr(acpr1.release_version,'\\d{1,}',1,2))
                                ) then  acpr2.release_version
                          else null
                         end case
                    from dual";

       $sql = "select  acpr2.release_version,acpr2.tracking_bug
               from  aru_cum_patch_releases acpr1,
                     aru_cum_patch_releases acpr2,
                     aru_bugfix_requests abr,
                     aru_cum_patch_series acps
               where acpr2.tracking_bug = abr.bug_number
                     and abr.status_id in (22,23,24)
                     and acpr2.series_id = acps.series_id
                     and acps.product_name like '".$ser_starts_with."%'
                     and abr.platform_id in (2000,$platform_id)
                     and acps.base_release_id = $base_release_id
                     and  acpr1.release_id = $cpm_rel_id
                     and acps.patch_type in (96021,96022,96023)
                     and acpr2.status_id in (34522, 34523, 34524,34529)
                     and acpr2.tracking_bug not in ($tracking_bug)
                     and acpr2.release_version in ($main_criteria)
                     and nvl(to_number(to_char(to_date(regexp_substr(acpr2.release_version,'(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\\d{4}',1,1,'i'),'monyyyy'),'yyyymm')),0)
                     <= nvl(to_number(to_char(to_date(regexp_substr(acpr1.release_version,'(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\\d{4}',1,1,'i'),'monyyyy'),'yyyymm')),999999)
                     order by to_number(substr(aru_cumulative_request.get_version(acpr2.release_version),instr(aru_cumulative_request.get_version(acpr2.release_version),'.',-1)+1,length(acpr2.release_version))) desc
                     ";
      @result = ARUDB::dynamic_query($sql);
      tie %op, 'Tie::IxHash';
      for(@result){
         my $patch = $_->[1];
         my $version= $_->[0];
         $op{$patch}{'patch_number'}= $patch;
         $op{$patch}{'release_version'} = $version;
      }
       if(%op){
              $error    = '';
              $prev_patches = encode_json \%op;
              goto LABEL;
          }


LABEL:
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "previous_patches" : $prev_patches
         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;


}

sub get_previous_releases{
  my ($self, $cgi, $req) = @_;
  my $release_id = $cgi->param('release_id');
  my $response;
  my $error;
  my $releases;
  if ($release_id =~ /^\d+$/){
   my  @params = (
               {
                name => 'pn_release_id',
                data =>  $release_id
               }
              );
    ($releases, $error) = ARUDB::exec_sf
               ('aru_cumulative_request.get_previous_releases',
                @params);
     $response = 'Success';
     if($error){
       $response = 'Failed';
     }
  goto LABEL;

  }else{
     $response = 'Failed';
     $error = 'Please provide the valid release_id';
  goto LABEL;
  }

LABEL:
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "prvious_releases" : "$releases"
         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;

}
sub get_cr_status{
  my ($self, $cgi, $req) = @_;
  my $request_id = $cgi->param('request_id');
  my $ret_json;
  if(!$request_id or $request_id !~ /^\d+$/){
   $ret_json = <<JSON_RET;
         {
           "status_id": "",
           "description":"",
           "error": "Invalid Request Id"
         }
JSON_RET
  }
my $status_id;
my $description;
if($request_id && $request_id =~ /^\d+$/ ){
  my $sql = "select acs.status_id,acs.description
             from  aru_cum_codeline_requests accr,
                   aru_status_codes acs
             where accr.status_id = acs.status_id
             and   accr.codeline_request_id = $request_id";
  my ($result) = ARUDB::dynamic_query($sql);
   ($status_id,$description) = @$result if($result);
  if(!$status_id){
    $ret_json = <<JSON_RET;
         {
           "status_id": "",
           "description":"",
           "error": "Invalid Request Id"
         }
JSON_RET

  }else{
    $ret_json = <<JSON_RET;
         {
           "status_id": $status_id,
           "description": $description,
           "error": ""
         }
JSON_RET


  }
}
        print STDOUT $cgi->header("Content-Type: text/json");
        print STDOUT $ret_json;

}

sub add_request_coments{
 my ($self, $cgi, $req) = @_;
 my $request_id  = $cgi->param('request_id');
 my $comments    = $cgi->param('comment');
 my $type        = $cgi->param('type') || 'Other';
 my $ret_json;
 if (!$request_id || $request_id !~ /^\d+$/){
     $ret_json = <<JSON_RET;
         {
           "status":"Failed",
           "error": "Invalid Request Id"
         }
JSON_RET

 }elsif(!$comments){
   $ret_json = <<JSON_RET;
         {
           "status":"Failed",
           "error": "Invalid Comments"
         }
JSON_RET


 }
my ($codeline_request_id,$status_id);
if($request_id && $request_id =~ /^\d+$/){
 my $sql = "select codeline_request_id,status_id
            from   aru_cum_codeline_requests
            where  codeline_request_id = $request_id";

 my ($result) = ARUDB::dynamic_query($sql);
    ($codeline_request_id,$status_id) = @$result if($result);

}

if(!$codeline_request_id){
$ret_json = <<JSON_RET;
         {
           "status":"Failed",
           "error": "Invalid Request Id"
         }
JSON_RET


}

if($codeline_request_id && $comments && $type){
 my ($hist_id,@params,$error);
    @params = (
               {
                name => 'pn_codeline_request_id',
                data =>  $codeline_request_id
               },
               {
                name => 'pv_comment_type',
                data => $type
               },
               {name => 'pv_comments',
                data => $comments
               },
               {name => 'pn_status_id',
                data => $status_id
               },
               {
                name => 'pn_last_updated_by',
                data => 1
               }

              );
    ($hist_id, $error) = ARUDB::exec_sf
               ('aru_cumulative_request.create_codeline_request_hist',
                @params);

   if($error){
     $ret_json = <<JSON_RET;
         {
           "status":"Failed",
           "error": "Error in saving comment"
         }
JSON_RET

   }elsif($hist_id){
   $ret_json = <<JSON_RET;
         {
           "status":"Success",
           "error": ""
         }
JSON_RET
   }
}
        print STDOUT $cgi->header("Content-Type: text/json");
        print STDOUT $ret_json;

}

sub _create_gi_series_release{
   my ($self,$GI_series, $src_prod_id, $GI_series_prod, $dest_family_name,
       $dest_series_product, $patch_desc,$user_id,$base_rel_id,
       $dest_version, $gi_rel_version, $source_series, $source_series_id,
       $src_patch_type) = @_;

   my $max_RU_OR_RUR;
   my $SeriesProduct = $GI_series_prod =~ s/(?<=GI).*//r;
   if ($patch_desc eq "Release Update")
   {
     $max_RU_OR_RUR =
       ARUForms::FastBranchSetup::get_max_RU_version($base_rel_id,
                                                     $SeriesProduct);
   }
   elsif ($patch_desc eq "Release Update Revision")
   {
     $max_RU_OR_RUR =
       ARUForms::FastBranchSetup::get_max_RUR_version($base_rel_id,
                                                      $SeriesProduct);
   }
   my $temp = $GI_series_prod  =~ s/(?<=GI).+/%/r;
   my $pt = join '', map {uc substr $_, 0, 1} split ' ', $patch_desc;
   $temp = uc $temp.$pt;
   my $rel_version = "$max_RU_OR_RUR"."%"."$temp";
   $dest_family_name = uc $GI_series_prod.$pt;
   $dest_family_name =~ s/\s+//gi;

   my $sql = "select acpr2.release_id, acpr2.series_id, acpr2.tracking_bug,
                     acps.series_name
                from aru_cum_patch_releases acpr, aru_cum_patch_releases acpr2,
                     aru_cum_patch_series acps
               where acpr.release_version like '$rel_version'
                 and acpr.series_id = acpr2.series_id
                 and acpr2.series_id = acps.series_id
                 and aru_backport_util.get_numeric_version(
                 acpr2.release_version) <=
                  aru_backport_util.get_numeric_version(acpr.release_version)
                 and acpr2.tracking_bug is not null
                 and acpr2.status_id not in (34528)
        	 order by acpr2.release_id desc";
   my @results = ARUDB::dynamic_query($sql);

   my $gi_src_rel_id;
   $gi_src_rel_id = $results[0]->[0];
   my $gi_src_series_id = $results[0]->[1];
   my $gi_source_patch = $results[0]->[2];
   my $gi_source_series = $results[0]->[3];

   my $created_from;
   if(!$self->is_ru_dev_series($source_series)
                && ($src_patch_type == 96021 ||
                      $src_patch_type == 96022 )){

     my $sql = "select release_id
                       from   aru_releases
                       where  release_id in (
                              select max(aru_release_id)
                              from   aru_cum_patch_releases
                              where  series_id = $source_series_id
                              and    status_id  in (34529,34524,34523,34522)
                       )";
     my @result = ARUDB::dynamic_query($sql);
     $created_from  = $result[0]->[0];
   }
   if(!$created_from){
       $created_from = $base_rel_id;
    }

   my $comment = "This Series is getting created from $source_series ".
                 "from fast branch setup API.";
   my $gi_series_id;
   my $error;
   my $response;
   my $abs_req_id = $self->{'abs_req_id'};

   my $sql ="select series_id
                  from   aru_cum_patch_series
                  where  series_name='".$GI_series."'";

   my @result = ARUDB::dynamic_query($sql);
   $gi_series_id = $result[0]->[0];
   add_abs_log_info($abs_req_id,96451,
             "GI Series:$GI_series already exists")  if ($gi_series_id);
   if (!$gi_series_id)
   {
       my @params = ({name => "pn_aru_product_id",
                      data => $src_prod_id},
                     {name => "pv_family_name",
                      data => uc($dest_family_name)},
                     {name => "pv_product_name",
                      data => $GI_series_prod},
                     {name => "pv_patch_type" ,
                      data => $patch_desc},
                     {name => "pv_status",
                      data => 'Active'},
                     {name => "pn_user_id",
                      data => $user_id},
                     {name => "pn_base_release_id",
                      data => $base_rel_id},
                     {name => "pv_comments" ,
                      data => $comment},
                     {name => "pno_series_id" ,
                      data => \$gi_series_id},
                     {name => "pv_new_rel_version",data=>$dest_version}
                  );
       if($gi_series_id){
           add_abs_log_info($abs_req_id,96451,
                            "Series:$GI_series Successfully Created!.");
       }
       my $err = ARUDB::exec_sp('aru_cumulative_request.create_series'
                                ,@params
                               );
       if($err){
                  $response = 'Failed';
                  $error = $err;
                  add_abs_log_info($abs_req_id,96451,
                    "Error in creating the GI Series:$GI_series ,".$err);
             }
        }
        if ($gi_series_id) {
             #
             # store the Source fast branch tracking bug details
             #
             my @params = (
                  {name => "pn_series_id",
                   data => $gi_series_id
                  },
                  {name => "pv_parameter_name",
                   data => "Source_Fast_Branch"
                  },
                  {name => "pn_parameter_type",
                   data =>  96183
                  },
                  {name => "pv_parameter_value",
                   data =>  $gi_source_patch
                  },
                  {name => "pn_user_id",
                   data => $user_id}
                  );

       my $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                                ,@params);
       add_abs_log_info($abs_req_id,96451,
                        'Activating the Destination Series...');
       $err =  ARUDB::exec_sp('aru_cumulative_request.update_cum_patch_series'
                               ,$gi_series_id,'status_id',34511,$user_id);
       @params = (
                       {name => "pn_series_id",
                        data => $gi_series_id
                       },
                       {name => "pv_parameter_name",
                        data => "series_created_from"
                       },
                       {name => "pn_parameter_type",
                        data =>  96183
                       },
                       {name => "pv_parameter_value",
                        data => $created_from
                       },
                       {name => "pn_user_id",
                        data => $user_id}
                     );

       $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                               ,@params);

       add_abs_log_info($abs_req_id,96452,
                          'Fetching Content Request Products Info...');
       my $sql = "select bugdb_prod_id,component,
                         comp_criteria,sub_components,
                         sub_comp_criteria
                   from  aru_cum_content_req_prods
                  where  series_id= $gi_src_series_id";

       my @results = ARUDB::dynamic_query($sql);
          add_abs_log_info($abs_req_id,96452,
                    'Adding Content Request Products to Destination Series...');
       foreach my $rec (@results){

           my $bugdb_prod_id  = $rec->[0];
           my $component      = $rec->[1];
           my $comp_criteria  = $rec->[2];
           my $sub_components = $rec->[3];
           my $sub_comp_criteria = $rec->[4];

          @params = (
                    {name => "pn_series_id",
                      data =>  $gi_series_id},
                     {name => "pn_bugdb_id",
                      data => $bugdb_prod_id
                     },
                     {name => "pv_component",
                      data => $component
                     },
                     {name => "pv_comp_criteria",
                      data => $comp_criteria
                     },
                     {name => "pv_sub_comp_list",
                      data => $sub_components
                     },
                     {name => "pv_sub_comp_criteria",
                      data => $sub_comp_criteria
                     },
                     {name => "pn_user_id",
                      data => $user_id
                     }
                    );
        eval{
         $err = ARUDB::exec_sp(
                 'aru_cumulative_request.add_content_req_products',
                  @params) if($gi_series_id);
        };
         add_abs_log_info($abs_req_id,96452,
                'Error in Adding the content request Products,'.$err) if($err);
                }
         add_abs_log_info($abs_req_id,96452,
                          'Fetching Source Series Parameters...');

         $sql = "select parameter_name,parameter_value,parameter_type
                  from   aru_cum_patch_series_params
                  where  series_id= $gi_src_series_id
                  and    parameter_type not in(90035,34590,34600,34601,
                         34602,34591,34603,34604,34605,34606,34666,96183
                  )";
        @results = ARUDB::dynamic_query($sql);
        add_abs_log_info($abs_req_id,96452,
                        'Adding Parameters to Destination Series...');
        foreach my $rec (@ results){
         my $parameter_name  = $rec->[0];
         my $parameter_value = $rec->[1];
         my $parameter_type  = $rec->[2];
         my @params = (
                        {       name => "pn_series_id",
                                data => $gi_series_id
                        },
                        {       name => "pv_parameter_name",
                                data => $parameter_name
                        },
                        {       name => "pn_parameter_type",
                                data => $parameter_type
                        },
                        {       name => "pv_parameter_value",
                                data => $parameter_value
                        },
                        {       name => "pn_user_id",
                                data => $user_id
                        }
                         );
           eval{
                  $err = ARUDB::exec_sp(
                       'aru_cumulative_request.add_series_parameters',
                        @params
                        ) if($gi_series_id);
                 };
       add_abs_log_info($abs_req_id,96452,
               "Error in Adding $parameter_name to Destination Series. $err")
                if($err);
                        }

        $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                                ,@params
                 );

        $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                            ,$gi_series_id
                            ,'Series Family Description'
                            ,'34530',uc($dest_family_name)
                            ,$user_id
                            ) if($dest_family_name !~ /^BI/gi  &&
                                 $dest_family_name !~ /^SOA/gi &&
                                 $dest_family_name !~ /^OAM/gi &&
                                 $dest_family_name !~ /^ADF/gi &&
                                 $dest_family_name !~ /^OIM/gi &&
                                 $dest_family_name !~ /^Web/gi);

        $sql = "select owner_type,email_address,
                       notification
                from   aru_cum_patch_series_owners
                where  series_id = $gi_src_series_id";

        @results = ARUDB::dynamic_query($sql);

        foreach my $rec (@results){

            my $owner_type    = $rec->[0];
            my $email_address = $rec->[1];
            my $notification  = $rec->[2];

            @params = (
                     {     name => "pn_series_id",
                           data =>  $gi_series_id
                     },
                     {     name => "pv_owner_type",
                           data => $owner_type
                     },
                     {     name => "pv_email_address",
                           data => $email_address
                     },
                     {     name => "pv_notification" ,
                           data => $notification
                     },
                     {     name => "pn_user_id",
                           data => $user_id
                     }
                                );
                $err = ARUDB::exec_sp('aru_cumulative_request.add_series_owners'
                                      ,@params
                                     );
          }
           $sql ="select approval_level,approver_type,
                         approver_id
                  from   aru_cum_patch_series_levels
                  where  series_id = $gi_src_series_id";

           @results = ARUDB::dynamic_query($sql);

           add_abs_log_info($abs_req_id,96452,"Adding Series Approval Levels");

           foreach my $rec (@results){
                        my $approval_level    = $rec->[0];
                        my $approver_type     = $rec->[1];
                        my $approver_id       = $rec->[2];

                        @params = (
                                {
                                 name => "pn_series_id",
                                 data =>  $gi_series_id
                                },
                                {
                                  name => "pn_approval_level",
                                  data => $approval_level
                                },
                                {
                                  name => "pv_approver_type",
                                  data => $approver_type
                                },
                                {
                                  name => "pn_approver_id",
                                  data => $approver_id
                                },
                                {
                                  name => "pn_user_id",
                                  data => $user_id
                                }
                     );

           eval{
             $err = ARUDB::exec_sp('aru_cumulative_request.add_series_approvals'
                                  ,@params
                                  );
           };
      add_abs_log_info($abs_req_id,96452,
                       "Error in adding the approval levels.$err") if($err);
                        }

      $sql = "select attribute_name,attribute_type,
                   attribute_value,attribute_default,
                   attribute_required,attribute_validation,
                   attribute_gap,attribute_order,
                   attribute_level,help_code
            from   aru_cum_patch_series_attrs
            where  series_id= $gi_src_series_id";
      @results = ARUDB::dynamic_query($sql);
      add_abs_log_info($abs_req_id,96452,'Adding Series attributes...');
      foreach my $rec (@results){

         my $attribute_name       = $rec->[0];
         my $attribute_type       = $rec->[1];
         my $attribute_value      = $rec->[2];
         my $attribute_default    = $rec->[3];
         my $attribute_required   = $rec->[4];
         my $attribute_validation = $rec->[5];
         my $attribute_gap        = $rec->[6];
         my $attribute_order      = $rec->[7];
         my $attribute_level      = $rec->[8];
         my $help_code            = $rec->[9];
         if($attribute_name eq 'BUNDLE_LABEL_SERIES'){
          $attribute_value =~  s/(\d+).(\d+).(\d+).(\d+)/$dest_version/gi;
          $attribute_default =~
                   s/(\d+).(\d+).(\d+).(\d+).(\d+)/$dest_version/gi;
         }
         @params = ({name => "pn_series_id",
                      data => $gi_series_id},
                     {name => "pv_attribute_name",
                      data => $attribute_name},
                     {name => "pv_attribute_type",
                      data => $attribute_type},
                     {name => "pv_attribute_value" ,
                      data => $attribute_value},
                     {name => "pv_attribute_default",
                      data => $attribute_default},
                     {name => "pv_attribute_required",
                      data => $attribute_required},
                     {name => "pv_attribute_validation",
                      data => $attribute_validation},
                     {name => "pv_attribute_gap" ,
                      data => $attribute_gap},
                     {name => "pn_attribute_order" ,
                      data => $attribute_order},
                     {name => "pn_attribute_level",
                      data=>$attribute_level},
                     { name => "pn_user_id",
                        data => $user_id
                     }
                  );
         eval{
          $err = ARUDB::exec_sp('aru_cumulative_request.add_series_attributes',
                                @params);
          };
          add_abs_log_info($abs_req_id,96452,
                         'Error in adding Series Attributes.'.$err) if($err);
          }
            my $gi_rel_id  =
                $self->_create_release($GI_series,$gi_rel_version,$user_id,
                $gi_src_rel_id) if($gi_series_id);

             if(!$gi_rel_id){
                $response = 'Failed';
                $error="Error in Creating the Release for $gi_series_id";
                add_abs_log_info($abs_req_id,96451,
                 "Error in creating the GI release");
                 }
          if($gi_rel_id){
              $sql  = "select status_id
                       from   aru_cum_patch_releases
                       where  release_id = $gi_rel_id";

              @results = ARUDB::dynamic_query($sql);

              if($results[0]->[0] != 34522 ){

                $err  = $self->_update_release_status($gi_rel_id,
                                                        34526,
                                                        $user_id);
                $err  = $self->_update_release_status($gi_rel_id,
                                                        34522,
                                                        $user_id);
              }
}
}
};

sub fast_branch_setup{
  my($self,$cgi,$req) = @_;
  my $source_series                                     = $cgi->param('source_series');
  my $destination_series                = $cgi->param('destination_series');
  my $source_patch                                      = $cgi->param('source_patch');
  my $destination_branch                = $cgi->param('destination_branch');
  my $dest_series_family                = $cgi->param('dest_series_family');
  my $destination_label     = $cgi->param('dest_label');
  my $source_label          = $cgi->param('source_label');
  my $source_branch         = $cgi->param('source_branch');
  my $log_file;
  my $response;
  my $error;
  my $json_decoded = '';
  my $patch_type;
  my $series_product;
  my $dest_series_exists;
  my $err;
  my $patch_desc;
  my $dest_ser_id;
  my $timestamp    = POSIX::strftime("%d-%b-%Y-%R:%S", localtime());
  my $logger        = ARUForms::ARUForm::new("ARUForms::LogViewer");
  log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,'',$timestamp,-1);
   if($ENV{REQUEST_METHOD} eq 'POST'){
      if($cgi->param('POSTDATA')){
        my $postdata = $cgi->param('POSTDATA');
        eval{
           $json_decoded = decode_json($postdata);
           1;
        }or
        do{
            $error = 'Not a valid JSON input.';
            $response = 'Failed';
            goto LABEL;
        };
           $source_series                               =       $json_decoded->{'source_series'};
           $destination_series  = $json_decoded->{'destination_series'};
           $source_patch                                = $json_decoded->{'source_patch'};
           $destination_branch  = $json_decoded->{'destination_branch'};
           $dest_series_family  = $json_decoded->{'dest_series_family'};
           $destination_label   = $json_decoded->{'dest_label'};
           $source_label        = $json_decoded->{'source_label'};
           $source_branch       = $json_decoded->{'source_branch'};

      }

   }
  my $dest_series = $destination_series;
  my $temp_series = $destination_series;
  if(!$source_series){
      $response = 'Failed';
      $error    = 'Invalid Source Series.';
      goto LABEL;
    }

  my $sql = "select series_name,series_id
            ,base_release_id,product_id
             from   aru_cum_patch_series
             where  series_name  ='".$source_series."'";

  my @results = ARUDB::dynamic_query($sql);

  if( scalar(@results) < 1){
      $response = 'Failed';
      $error    = 'Invalid Source Series.';
      goto LABEL;
    }
  my $src_series_id = $results[0]->[1];
  my $src_base_rel_id = $results[0]->[2];
  my $src_aru_product = $results[0]->[3];
    if(!$dest_series_family){

      $response = 'Failed';
      $error    = 'Invalid Destination Series Family Name.';
      goto LABEL;

  }

  if(!$destination_series){
      $response = 'Failed';
      $error    = 'Invalid Destination Series.';
      goto LABEL;
   }

  if($source_patch !~ /^\d+$/){
      $response = 'Failed';
      $error    = 'Invalid Source Patch.';
      goto LABEL;

  }
  log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,'',$timestamp,-1);
  $log_file = '/ARUForms/LogViewer/process_form?log='.FAST_BRANCH_DIR."/$source_patch".
                           "/$timestamp.idx";

  if($destination_series !~ /Bundle Patch|Patch Set Update|Security Patch Update|System Patch|Release Update|Release Update Revision|Cloud Emergency Update|Release Update Extension|Release Update Increment/gi){
      $response = 'Failed';
      $error    = 'Destination Series shoud contain valid patch description Eg:Bundle Patch , Release Update.';
      log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
      goto LABEL;

  }
  if($destination_series !~ /\s+((\d+)\.){4}(\d+)$/gi){

      $response = 'Failed';
      $error    = 'Destination Series name should contain valid 5 digit version.';
      log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
      goto LABEL;

  }
   $destination_series =~ /(((\d+)\.){2,4}(\d+))$/;
   my $dest_version = $1;
   $sql = "select series_name,series_id
           from   aru_cum_patch_series
           where  series_name='".$dest_series."'";
  @results = ARUDB::dynamic_query($sql);

  if( scalar(@results) > 0){
         $dest_series_exists = 1;
         $dest_ser_id = $results[0]->[1];
    }

  if($dest_series =~ m/Bundle Patch/gi){
      $patch_type = 34501;
      $patch_desc = 'Bundle Patch';
      $temp_series =~ s/\s+Bundle Patch(\s){1}(((\d+)\.){2,4}(\d+))$//gi;
      if($dest_series_family !~ /BP$/){
              $response = 'Failed';
                                $error    = 'Destination Series Family Name should have suffix BP';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
                                goto LABEL;
      }
  }elsif($dest_series =~ m/Patch Set Update(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 34502;
      $patch_desc = 'Patch Set Update';
      $temp_series =~ s/\s+Patch Set Update(\s){1}(((\d+)\.){2,4}(\d+))$//gi;
      if($dest_series_family !~ /PSU$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix PSU';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }

  }elsif($dest_series =~ m/Security Patch Update(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 34503;
      $patch_desc = 'Security Patch Update';
      $temp_series =~ s/\s+Security Patch Update(\s){1}(((\d+)\.){2,4}(\d+))$//gi;
     if($dest_series_family !~ /SPU$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix SPU';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }


  }elsif($dest_series =~ m/System Patch(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 35350;
      $patch_desc ='System Patch';
      $temp_series =~ s/\s+System Patch(\s){1}(((\d+)\.){2,4}(\d+))$//gi;

     if($dest_series_family !~ /SP$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix SP';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }

  }elsif($dest_series =~ m/Release Update(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 96021;
      $patch_desc = 'Release Update';
      $temp_series =~ s/\s+Release Update(\s){1}(((\d+)\.){2,4}(\d+))$//gi;

     if($dest_series_family !~ /RU$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix RU';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }

  }elsif($dest_series =~ m/Release Update Revision(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 96022;
      $patch_desc = 'Release Update Revision';
      $temp_series =~ s/\s+Release Update Revision(\s){1}(((\d+)\.){2,4}(\d+))$//gi;

     if($dest_series_family !~ /RUR$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix RUR';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }

  }elsif($dest_series =~ m/Cloud Emergency Update(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 96023;
      $patch_desc = 'Cloud Emergency Update';
      $temp_series =~ s/\s+Cloud Emergency Update(\s){1}(((\d+)\.){2,4}(\d+))$//gi;

     if($dest_series_family !~ /CEU$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix CEU';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }

  }elsif($dest_series =~ m/Release Update Extension(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 96084;
      $patch_desc = 'Release Update Extension';
      $temp_series =~ s/\s+Release Update Extension(\s){1}(((\d+)\.){2,4}(\d+))$//gi;

     if($dest_series_family !~ /RUE$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix RUE';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }

  }elsif($dest_series =~ m/Release Update Increment(\s){1}(((\d+)\.){2,4}(\d+))$/gi){
      $patch_type = 96085;
      $patch_desc = 'Release Update Increment';
      $temp_series =~ s/\s+Release Update Increment(\s){1}(((\d+)\.){2,4}(\d+))$//gi;

     if($dest_series_family !~ /RUI$/){
              $response = 'Failed';
              $error    = 'Destination Series Family Name should have suffix RUI';
              log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
              goto LABEL;
      }

  }
   $series_product = $temp_series;


  if($source_patch !~ /^\d+$/){
      $response = 'Failed';
      $error    = 'Invalid Source Patch.';
      goto LABEL;

  }
 $sql = "select label,patch, regexp_substr
                    (label,
                    '(\\d{6,})(\\.)?(\\d{4,})?'
                    ) as label_date
        from
        (select release_label as label,to_char(tracking_bug) as patch
         from   aru_cum_patch_releases r,
                aru_cum_patch_series s
         where  r.tracking_bug = $source_patch
         and    r.series_id = s.series_id
         and    s.series_id = $src_series_id
         union
         select parameter_name as label ,parameter_value as patch
         from   aru_cum_patch_release_params rp,
                aru_cum_patch_releases r,
                aru_cum_patch_series s
         where  rp.parameter_value = to_char($source_patch)
         and    rp.release_id = r.release_id
         and    r.series_id   = s.series_id
         and    s.series_id   = $src_series_id
         and    rp.parameter_type = 34593)
        where rownum < 2
         ";
if($dest_ser_id){
 $sql = "select label,patch, regexp_substr
                    (label,
                    '(\\d{6,})(\\.)?(\\d{4,})?'
                    ) as label_date
        from
        (select release_label as label,to_char(tracking_bug) as patch
         from   aru_cum_patch_releases r,
                aru_cum_patch_series s
         where  r.tracking_bug = $source_patch
         and    r.series_id = s.series_id
         and    s.series_id in($src_series_id,$dest_ser_id)
         union
         select parameter_name as label ,parameter_value as patch
         from   aru_cum_patch_release_params rp,
                aru_cum_patch_releases r,
                aru_cum_patch_series s
         where  rp.parameter_value = to_char($source_patch)
         and    rp.release_id = r.release_id
         and    r.series_id   = s.series_id
         and    s.series_id   in ($src_series_id,$dest_ser_id)
         and    rp.parameter_type = 34593)
        where rownum < 2
         ";


}
 @results = ARUDB::dynamic_query($sql);
 if( scalar(@results) < 1){
      $response = 'Failed';
      $error    = "Source Patch:$source_patch is not associated to Source Series:$source_series";
      log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
      goto LABEL;
 }

my $src_label = $results[0]->[0];
my $build_time = $results[0]->[2];
if($source_label){
  if($source_label =~ /(\d+\.){1,4}((\d+)(\.\d+)?)/gi){
     $build_time = $2
  }
}

my $dst_label;
$sql = "select bug_number
                                from   aru_bugfix_requests
                                where  bug_number = $source_patch";
 @results = ARUDB::dynamic_query($sql);
 if( scalar(@results) < 1){
      $response = 'Failed';
      $error    = "In valid Source Patch.";
      log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
      goto LABEL;
 }
if($destination_label){
 if($destination_label =~ /(\d+\.){1,4}((\d+)(\.\d+)?)/gi ){
  $dst_label=$destination_label;
  $build_time = $2;
 }

}


my $build_date;
if($build_time =~ /(\d+)\.?(\d+)?/) {
              $build_date = $1;
}


$sql = "select release_id,status_id
        from   aru_cum_patch_releases
        where  series_id = $src_series_id
        and    tracking_bug = $source_patch";
@results = ARUDB::dynamic_query($sql);

my $src_rc_rel_id;
my $src_rc_status;
$src_rc_rel_id = $results[0]->[0];
$src_rc_status = $results[0]->[1];



  if($source_series eq $destination_series){
      $response = 'Failed';
      $error    = 'Source Series name and Destination Series name should not be same.';
      log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
      goto LABEL;

  }

my $comment = "This Series is created from $source_series from fast branch setup API.";
my $msg ="Creating Destination Series : $destination_series";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);
my @params = ({name => "pn_aru_product_id",
                      data => $src_aru_product},
                     {name => "pv_family_name",
                      data => $dest_series_family},
                     {name => "pv_product_name",
                      data => $series_product},
                     {name => "pv_patch_type" ,
                      data => $patch_desc},
                     {name => "pv_status",
                      data => 'Active'},
                     {name => "pn_user_id",
                      data => 1},
                     {name => "pn_base_release_id",
                      data => $src_base_rel_id},
                     {name => "pv_comments" ,
                      data => $comment},
                     {name => "pno_series_id" ,
                      data => \$dest_ser_id},
                     {name => "pv_new_rel_version",data=>$dest_version}
                  );
$err = ARUDB::exec_sp('aru_cumulative_request.create_series',
                                @params) if(!$dest_series_exists);
if($err){
  $response = 'Failed';
  $error    = 'Destination Series Creation Failed '.$err;
  log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
  goto LABEL;
}

$msg ="Destination Series Created : $destination_series";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);
$msg = "copying Source Series Parameters to Destination Series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);
                $sql = "select parameter_name,parameter_value
                        ,parameter_type
                        from   aru_cum_patch_series_params
                        where  series_id= $src_series_id
                        and    parameter_type not in (90035,34590,34600,34601,34602,34591,
                                    34603,34604,34605,34606,34666)";

    @results = ARUDB::dynamic_query($sql);
    foreach my $rec (@results){
         my $parameter_name  = $rec->[0];
         my $parameter_value = $rec->[1];
         my $parameter_type  = $rec->[2];
           if($parameter_name eq 'Series Branch Name' && $parameter_value){
              if($destination_branch){
                $parameter_value = $parameter_value.','.$destination_branch;
              }

           }elsif($parameter_name eq 'Series Branch Name' && !$parameter_value){
               if($destination_branch){
                $parameter_value = $destination_branch;
               }

           }
             @params = ({name => "pn_series_id",
                      data =>    $dest_ser_id},
                     {name => "pv_parameter_name",
                      data => $parameter_name},
                     {name => "pn_parameter_type",
                      data => $parameter_type},
                     {name => "pv_parameter_value" ,
                      data => $parameter_value}
                  );
           $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters',
                                @params) if($dest_ser_id);


    }

  $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters',
                                $dest_ser_id,'Continuous Dated Release','34530','Yes',1) if($dest_ser_id);

$msg = "copying Source Series Owners to Destination Series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);


     $sql = "select owner_type,email_address,
                    notification
             from   aru_cum_patch_series_owners
             where  series_id = $src_series_id";
     @results = ARUDB::dynamic_query($sql);

    foreach my $rec (@results){
         my $owner_type    = $rec->[0];
         my $email_address = $rec->[1];
         my $notification  = $rec->[2];

             @params = ({name => "pn_series_id",
                      data =>    $dest_ser_id},
                     {name => "pv_owner_type",
                      data => $owner_type},
                     {name => "pv_email_address",
                      data => $email_address},
                     {name => "pv_notification" ,
                      data => $notification}
                  );
           $err = ARUDB::exec_sp('aru_cumulative_request.add_series_owners', @params) if($dest_ser_id);


    }
$msg = "Copying  approval levels from Source Series to Destination Series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);

     $sql ="select approval_level,approver_type,
                   approver_id
            from   aru_cum_patch_series_levels
            where  series_id = $src_series_id";

     @results = ARUDB::dynamic_query($sql);

    foreach my $rec (@results){
         my $approval_level    = $rec->[0];
         my $approver_type     = $rec->[1];
         my $approver_id       = $rec->[2];

             @params = ({name => "pn_series_id",
                      data =>    $dest_ser_id},
                     {name => "pn_approval_level",
                      data => $approval_level},
                     {name => "pv_approver_type",
                      data => $approver_type},
                     {name => "pn_approver_id" ,
                      data => $approver_id}
                  );
           $err = ARUDB::exec_sp('aru_cumulative_request.add_series_approvals', @params) if($dest_ser_id);


    }

$msg = "copying content request products from Source Series to Destination Series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);

    $sql = "select bugdb_prod_id,component,
                   comp_criteria,sub_components,
                   sub_comp_criteria
            from   aru_cum_content_req_prods
            where  series_id= $src_series_id";
    @results = ARUDB::dynamic_query($sql);
    foreach my $rec (@results){
             my $bugdb_prod_id  = $rec->[0];
             my $component      = $rec->[1];
             my $comp_criteria  = $rec->[2];
             my $sub_components = $rec->[3];
             my $sub_comp_criteria = $rec->[4];

          @params = ({name => "pn_series_id",
                      data =>    $dest_ser_id},
                     {name => "pn_bugdb_id",
                      data => $bugdb_prod_id},
                     {name => "pv_component",
                      data => $component},
                     {name => "pv_comp_criteria" ,
                      data => $comp_criteria},
                     {name => "pv_sub_comp_list",
                      data => $sub_components},
                     {name => "pv_sub_comp_criteria",
                      data => $sub_comp_criteria},
                     {name => "pn_user_id",
                      data => 1}
                  );
           $err = ARUDB::exec_sp('aru_cumulative_request.add_content_req_products', @params) if($dest_ser_id);

    }

$msg = "Copying attributes from Source Series to Destination Series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);
    $sql = "select attribute_name,attribute_type,
                   attribute_value,attribute_default,
                   attribute_required,attribute_validation,
                   attribute_gap,attribute_order,
                   attribute_level,help_code
            from   aru_cum_patch_series_attrs
            where  series_id= $src_series_id";
    @results = ARUDB::dynamic_query($sql);
    foreach my $rec (@results){
         my $attribute_name       = $rec->[0];
         my $attribute_type       = $rec->[1];
         my $attribute_value      = $rec->[2];
         my $attribute_default    = $rec->[3];
         my $attribute_required   = $rec->[4];
         my $attribute_validation = $rec->[5];
         my $attribute_gap        = $rec->[6];
         my $attribute_order      = $rec->[7];
         my $attribute_level      = $rec->[8];
         my $help_code            = $rec->[9];
         my @params = ({name => "pn_series_id",
                      data => $dest_ser_id},
                     {name => "pv_attribute_name",
                      data => $attribute_name},
                     {name => "pv_attribute_type",
                      data => $attribute_type},
                     {name => "pv_attribute_value" ,
                      data => $attribute_value},
                     {name => "pv_attribute_default",
                      data => $attribute_default},
                     {name => "pv_attribute_required",
                      data => $attribute_required},
                     {name => "pv_attribute_validation",
                      data => $attribute_validation},
                     {name => "pv_attribute_gap" ,
                      data => $attribute_gap},
                     {name => "pn_attribute_order" ,
                      data => $attribute_order},
                     {name => "pn_attribute_level",
                     data=>$attribute_level}
                  );
$err = ARUDB::exec_sp('aru_cumulative_request.add_series_attributes',
                                @params) if($dest_ser_id);


    }

$msg = "Creating The stream release :$destination_series .";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);

my $stream_rel_id  = $self->_create_release($destination_series,$dest_version,1) if($dest_ser_id);
if(!$stream_rel_id){
  $response = 'Failed';
  $error="Error in Creating the Release:$destination_series";
  $msg = "Creating The stream release :$destination_series .";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
  goto LABEL;

}
$err = $self->_update_release_status($stream_rel_id,34526,1);
if($err){
  $response = 'Failed';
  $error="Error in moving the Release:$destination_series Codeline Open Setup Status,$err";
  log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
  goto LABEL;

}
$err = $self->_update_release_status($stream_rel_id,34522,1);


if($err){
  $response = 'Failed';
  $error="Error in moving the Release:$destination_series Codeline Open Status,$err";
  $msg = "Creating The stream release :$destination_series .";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
  goto LABEL;

}
$msg = "Stream release moved to Codeline Open status.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);

my $ver_query ="select
                    aru_backport_util.ignore_fifth_segment(
                  aru_cumulative_request.get_series_version(
                    aru_backport_util.pad_version(
                    acps.series_name))
                    )
                    from
                        aru_releases ar,
                        aru_cum_patch_series acps
                    where
                        ar.release_id = acps.base_release_id
                    and acps.series_id=$dest_ser_id
           ";

my ($base_ver_res) = ARUDB::dynamic_query($ver_query);
my ($series_base_version) = @$base_ver_res if($base_ver_res);
my $version;
if($build_date && $series_base_version) {
                my $rel_ver = $series_base_version .".".$build_date;
                $version =  $self->get_release_version($series_base_version,$dest_ser_id,$build_date);
}else{

  $response = 'Failed';
  $error="Could not find the source patch dated label.";
log_fast_branch_setup($logger,$source_series,$destination_series,$error,$msg,$timestamp);
  goto LABEL;


}

my $lbl;
if($dst_label){
   $lbl = $dst_label;
}else{
  $lbl = $src_label;
}

my $release_candidate  = $self->_create_release($destination_series,$version,1) if($dest_ser_id);
if(!$release_candidate){
  $response = 'Failed';
  $error="Error in Creating the Release with  Release Candidate status";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
  goto LABEL;

}
$msg = "Created the release $version in Release candidate status";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);
$err = $self->_update_release_status($release_candidate,34529,1,$lbl);
if($err){
  $response = 'Failed';
  $error="Error in moving the Release:$version Release Candidate Status,$err";
  log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$error,$timestamp);
  goto LABEL;

}

if($release_candidate){
 ARUDB::exec_sp(
            'aru_cumulative_request.update_cum_patch_releases',
            $release_candidate,
            'tracking_bug',
            $source_patch,
            1
            );

}
$msg = "Source patch associated to Destination Series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);
$err = ARUDB::exec_sp('aru_cumulative_request.add_release_parameters',
                                $stream_rel_id,$lbl,$source_patch,34593) if($stream_rel_id);

$err = ARUDB::exec_sp('aru_cumulative_request.add_release_parameters',
                                $release_candidate,$lbl,$source_patch,34593) if($release_candidate);

$err = ARUDB::exec_sp('aru_cumulative_request.add_release_parameters',
                                $release_candidate,'validate_released','N',99999) if($release_candidate);


$msg = "Bootstraping the content from the source patch to destination series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);
$req->pool->cleanup_register(sub
                             {
$self->bootstrap_content($src_series_id,$source_patch,$dest_ser_id,$stream_rel_id);
});
$msg = "Updating Patch meta data.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);

$self->_update_patch_metadata($source_patch,$release_candidate);


$sql = "select distinct rp.parameter_name,rp.parameter_value,rp.release_id
        from   aru_cum_patch_release_params rp,
               aru_cum_patch_releases r
        where  rp.release_id = r.release_id
        and    r.series_id = $src_series_id
        and    parameter_value = to_char($source_patch)
        and    parameter_type =34593";
my @result = ARUDB::dynamic_query($sql);

  foreach my $rec (@result){
            my $name  = $rec->[0];
            my $value = $rec->[1];
            my $id    = $rec->[2];
            $err = ARUDB::exec_sp('aru_cumulative_request.add_release_parameters',
                                $id,$name,$value,34617);
  }

if($src_rc_rel_id){

 ARUDB::exec_sp(
            'aru_cumulative_request.update_cum_patch_releases',
            $src_rc_rel_id,
            'tracking_bug',
            '',
            1
            );

$err = $self->_update_release_status($src_rc_rel_id,$src_rc_status,1);


}
$msg = "Disassociated the $source_patch  from Source Series.";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);


$response = 'Success';
$error='';

$msg = "Finished";
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,$msg,$timestamp);

LABEL:
log_fast_branch_setup($logger,$source_series,$destination_series,$source_patch,'',$timestamp,1);
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "log_file" : "$log_file"
         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;


}

sub _update_patch_metadata{
   my($self,$patch,$release_id,$timestamp)=@_;
   my $sql = "select acr.release_version,acs.family_name,
                     acs.product_name,acs.base_release_id,
                     aru_backport_util.pad_version(ar.release_name),acs.patch_type,
                     aru_backport_util.ignore_fifth_segment(
                        aru_cumulative_request.get_version(acr.release_version))||'.0' ,
                     aru_cumulative_request.get_version(acr.release_version)
              from aru_cum_patch_releases acr,
                   aru_cum_patch_series acs,
                   aru_releases ar
              where acr.series_id= acs.series_id
              and   acs.base_release_id = ar.release_id
              and   acr.release_id = $release_id";

   my @result  = ARUDB::dynamic_query($sql);

   my $release_verison = $result[0]->[0];
   my $series_family   = $result[0]->[1];
   my $product_name    = $result[0]->[2];
   my $base_release_id = $result[0]->[3];
   my $base_verison    = $result[0]->[4];
   my $patch_type      = $result[0]->[5];
   my $version_5th0    = $result[0]->[6];
   my $version         = $result[0]->[7];

     $sql = "select description
             from   aru_status_codes
             where  status_id = $patch_type";
      @result  = ARUDB::dynamic_query($sql);
   my $patch_description = $result[0]->[0];

   my $is_new_rel_model = ARUDB::exec_sf_boolean('aru_cumulative_request.is_new_release_model',$base_release_id);
   $sql  = "select to_number(to_char(to_date(rptdate,
                  'YYYY-MM-DD HH24:MI:SS'),'YYMMDD.HH24MI'))
           from  bugdb_rpthead_v
           where rptno = $patch";
   @result  = ARUDB::dynamic_query($sql);
   $timestamp = $result[0]->[0];
   my $bug_version = $release_verison;
   my $subject     = $product_name.' '.$patch_description.' '.$version_5th0;
      $subject     = $product_name.' '.$patch_description.' '.$version_5th0.'(ID:'.$timestamp.')' if($timestamp);
   $subject = substr($subject,0,80);

  my @params = (
               {name => 'pn_bug_number',data=>$patch},
               {name => 'pv_do_by_release',data=>$bug_version},
               {name => 'pv_utility_version',data=> $base_verison},
               {name => 'pv_version',data=>$bug_version},
               {name => 'pn_status',data=>35},
               {name => 'pv_version_fixed',data=>$bug_version},
               {name => 'pv_abstract',data=>$subject}

              );
     my $error = ARUDB::exec_sp('bugdb.update_bug',
                            @params);
    @params = (
                {name => 'p_rptno',
                 data => $patch},
                {name => 'p_text' ,
                 data => "@ This bug was created by ARU while moving the release to Codeline Open and tracks the release $bug_version"}

              );
    $error = ARUDB::exec_sp('aru_backport_util.add_bug_text',
                            @params);
    my $delta_link = ARUDB::exec_sf('aru_backport_request.get_request_view_link',
                            "/ARU/CISearch/process_form?releases=$release_id");

    my $cumulative_link = ARUDB::exec_sf('aru_backport_request.get_request_view_link',
                          "/ARU/CISearch/process_form?releases=$release_id&link_type=cumulative");

        @params = (
                {name => 'p_rptno' ,
                 data => $patch
                },
                {name => 'p_text' ,
                 data => "@ To view the delta content for $bug_version, refer to @ $delta_link"
                }
                );
        $error = ARUDB::exec_sp('aru_backport_util.add_bug_text',
                            @params);
        @params = (
                {name => 'p_rptno' ,
                 data => $patch
                },
                {name => 'p_text' ,
                 data => "To view the cumulative content for $bug_version, refer to @ $cumulative_link"
                }
                );
        $error = ARUDB::exec_sp('aru_backport_util.add_bug_text',
                            @params);
}
sub _create_release
{
    my ($self,$series_name, $release_version,
             $user_id,$src_rel_id,$label) = @_;
    my ($release_id, $error);
    my $abs_req_id = $self->{'abs_req_id'};
    my $sql = "select release_id
               from   aru_cum_patch_releases acpr,
                      aru_cum_patch_series acps
               where  acpr.series_id = acps.series_id
               and    acps.series_name ='".$series_name."'
               and    acpr.release_version like '".$release_version."%'";
    my @result  = ARUDB::dynamic_query($sql);

    $release_id = $result[0]->[0];

   add_abs_log_info($abs_req_id,96453,"CPM Release already exists with the version $release_version") if($release_id);

    return $release_id if($release_id);
      $sql = "select family_name,base_release_id,
                      product_id,aru_cumulative_request.get_series_version(series_name)
               from   aru_cum_patch_series
               where  series_name ='".$series_name."'";
    @result = ARUDB::dynamic_query($sql);
    my $family_name = $result[0]->[0];
    my $base_rel_id = $result[0]->[1];
    my $prod_id     = $result[0]->[2];
    my $series_version = $result[0]->[3];

       $sql = "select developer_assigned,backport_comment
                     ,backport_assignment_message,release_label
               from   aru_cum_patch_releases
               where  release_id = $src_rel_id";

       @result = ARUDB::dynamic_query($sql);
    my $dev_assigned  = $result[0]->[0];
    my $backport_cmnt = $result[0]->[1];
    my $assign_msg    = $result[0]->[2];
    my $release_lbl   = $result[0]->[3];
=pod
       $sql =   "select substr(label_name,1,INSTR(label_name,'_',1,1))
                                                                 from   aru_product_release_labels
                                                                 where product_release_id in (
                         select product_release_id
                         from aru_product_releases
                         where release_id=$base_rel_id
                         and product_id =$prod_id)";
       @result = ARUDB::dynamic_query($sql);
=cut
    my $dest_rel_label = 'NA';
    my $label_prefix = 'NA';
    if ($label)
    {
      my $hiphen_index = index($label,'_');
      #my $label_prefix = 'NA';
      $label_prefix = substr($label,0,$hiphen_index+1) if($hiphen_index > 0);
     # $dest_rel_label = 'NA';
       if($label_prefix && $label_prefix ne 'NA'){
           $dest_rel_label = "$label_prefix"."$release_version".
                             "$family_name".'_LINUX.X64_RELEASE';
       }
     }

    add_abs_log_info($abs_req_id,96453,"Creating the Release $release_version.$family_name");
    my @params  =   ({name => "pv_series_name",
                      data => $series_name},
                     {name => "pv_release_version",
                      data => $release_version},
                     {name => "pv_developer_assigned",
                      data => $dev_assigned},
                     {name => "pv_backport_comment",
                      data => $backport_cmnt},
                     {name => "pv_backport_assignment_message",
                      data => $assign_msg},
                     {name => "pv_release_label",
                      data =>  $dest_rel_label},
                     {name => "pn_user_id",
                      data => $user_id},
                     {name => "pno_release_id",
                      data => \$release_id});
  eval{
    $error = ARUDB::exec_sp('aru_cumulative_request.create_release',
                            @params);
   };
   add_abs_log_info($abs_req_id,96453,"Error in creating the release version $release_version"."$error") if($error);
eval{
    if($release_id && $src_rel_id){
     add_abs_log_info($abs_req_id,96453,"CPM Release is created with version $release_version");
     $sql = "select ap.platform_name||'('||ap.platform_id||')',
                     arl.platform_release_label, arl.platform_id
                    ,regexp_substr(regexp_replace(arl.platform_release_label,'(.)+_(\\d+\\.){4}\\d+'),'_(.)+')
             from   aru_platforms ap,
                    aru_cum_plat_rel_labels arl
             where  ap.platform_id = arl.platform_id
             and   arl.release_id = $src_rel_id";

     @result = ARUDB::dynamic_query($sql);
       for(@result){
           my $pf_label = $_->[1];
           my $pf_num   = $_->[2];
           my $pf_name  = $_->[3];
           my $releaseFamily = $release_version.$family_name;
              $pf_label = $label_prefix.''.$releaseFamily.''.$pf_name;
add_abs_log_info($abs_req_id,96454,"Add Platform Label:$pf_label");

           my @params = ({name => "pn_release_id",
                          data => $release_id
                         },
                         {name => "pn_platform_id",
                          data => $pf_num
                         },
                         {name => "pv_platform_release_label",
                          data => $pf_label
                         },
                         {name => "pn_user_id",
                          data => $user_id
                         },
                         );
        $error = ARUDB::exec_sp(
                      'aru_cumulative_request.update_platform_release_label',
                                 @params) if($label_prefix);

        add_abs_log_info($abs_req_id,96454,"Error in Adding Platfrom label:$pf_label".",$error") if($error);
       }

    }
};
    return $release_id;
}

sub _update_release_status
{
    my($self,$release_id, $status,$user_id,$label) = @_;
    my $abs_req_id = $self->{'abs_req_id'};
    my($tracking_bug, $error);
    $label = 'NA' if(!$label);
    my $sql = "select developer_assigned,backport_comment
                     ,backport_assignment_message,release_label
                     ,release_version
               from   aru_cum_patch_releases
               where  release_id =$release_id";
    my %releaseStatus;
     $releaseStatus{'34521'} = 'Content Definition';
     $releaseStatus{'34526'} = 'Codeline Open Setup';
     $releaseStatus{'34522'} = 'Codeline Open';
     $releaseStatus{'34523'} = 'Codeline Frozen';
     $releaseStatus{'34524'} = 'Released';
     $releaseStatus{'34528'} = 'Cancelled';
     $releaseStatus{'34529'} = 'Release Candidate';

    my @result = ARUDB::dynamic_query($sql);
    my $dev_assigned  = $result[0]->[0];
    my $backport_cmnt = $result[0]->[1];
    my $assign_msg    = $result[0]->[2];
    my $release_lbl   = $result[0]->[3];
    my $releaseVersion = $result[0]->[4];

   add_abs_log_info($abs_req_id,96454,"Updating the Release:$releaseVersion status to ".$releaseStatus{$status});
    my @params = ( {name => "pn_release_id",
                    data => $release_id},
                   {name => "pv_developer_assigned",
                    data => $dev_assigned},
                   {name => "pv_backport_comment",
                    data => $backport_cmnt},
                   {name => "pv_backport_assignment_message",
                    data => $assign_msg},
                   {name => "pn_status_id",
                    data => $status},
                   {name => "pn_user_id",
                    data => $user_id},
                   {name => "pb_label_error",
                    data => 0,
                    type => "boolean"},
                   {name => "pv_release_label",
                    data => $release_lbl},
                   {name => "pno_tracking_bug",
                    data => \$tracking_bug} );
eval{
    $error = ARUDB::exec_sp('aru_cumulative_request.update_release',
                             @params);
};
 add_abs_log_info($abs_req_id,96454,'Error in updating the release status.'.$error)if($error);
   return $error;
}

sub bootstrap_content{
 use ConfigLoader "ISDSPF::Config" => $ENV{ISD_HOME}.'/conf/isdspf.pl';
 my ($self,$src_series_id,$patch,$series_id,$release_id,$label_date,$user_id) = @_;
 my $statusmsg;
 my $abs_req_id = $self->{'abs_req_id'};
=for comment 
 my $abs_req_id = $self->{'abs_req_id'};
 my $runUsingScript = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                               'RUN PYTHON DELTA CONTENT');
if(lc $runUsingScript == 'on'){
  eval{
     my $command = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                               'RUN PYTHON COMMAND');
    # my $command = "python -u /scratch/rchamant/prod/pls_33266325/isd/pm/ARUForms/remote_machine.py";
    my $remote_param = "config=dev&sub=bootstrap_content&abs_req_idscp=$abs_req_id&src_series_id=$src_series_id&patch=$patch&series_id=$series_id&release_id=$release_id&label_date=$label_date&user_id=$user_id"; 
    $command = $command." $remote_param";
    my $pid = open3(my $chld_in, my $chld_out, my $chld_err = gensym,$command);
    waitpid( $pid, 0 );
    my $child_exit_status = $? >> 8;
  };
}
# eval{
# # my $ret = system(`python -u /Users/rahulch/Downloads/AdvancedPython/remote_machine.py`);
# my $pid = open3(my $chld_in, my $chld_out, my $chld_err = gensym,
#                 'python -u /Users/rahulch/Downloads/AdvancedPython/remote_machine.py 1 2 4 5');
# print "Return value $pid";
# waitpid( $pid, 0 );

# # system ($ret) == 0 or die "command was unable to run to completion:\n$ret\n";
# };
my $temp_sql = "select count(*) from aru_cum_abs_req_info
                where abs_request_id = $abs_req_id
                and module_id = 96455
                and message like 'Python: Delta Content Bootstrap completed'";
my $temp_res = ARUDB::dynamic_query($temp_sql);
if ($temp_res->[0] == 1){
  return;
}
=cut
               

    $label_date =~ s/\.//gi;
    if(length($label_date) == 6){
       $label_date = $label_date.'0000';
    }
   if(!$user_id){
        $user_id = 1;
   }

  add_abs_log_info($abs_req_id,96455,"Fetching Detla contnet...");
  my $sql = "select release_id
             from   aru_cum_patch_releases
             where   release_name in (
              select series_name
              from   aru_cum_patch_series
              where  series_id = $src_series_id
             )";
  my @res =  ARUDB::dynamic_query($sql);
  my $stream_rel_id = $res[0]->[0];
     $sql = "select s.base_release_id,s.product_id
                   ,s.product_name,p.parameter_value,s.patch_type
             from  aru_cum_patch_series s,
                   aru_cum_patch_series_params p
             where s.series_id = p.series_id
             and   s.series_id = $src_series_id
             and   p.parameter_name = 'COMPONENT'";
      @res =  ARUDB::dynamic_query($sql);
  my $base_rel_id = $res[0]->[0];
  my $aru_prod_id = $res[0]->[1];
  my $series_prod = $res[0]->[2];
  my $comp        = uc($res[0]->[3]);
  my $patch_type  = $res[0]->[4];
  my @series_prods      = split('\s+',$series_prod);
  my $ser_starts_with   = $series_prods[0];
  my $prv_patch_types   = $patch_type;
     if($patch_type == 96021 || $patch_type == 96022
              || $patch_type == 96023 || 96085 ){
        $prv_patch_types = '96021,96022,96023,96085';
     }
     if($patch_type == 96021){
        $prv_patch_types = '96021';
     }
  $sql = "select distinct accr.base_bug,accr.codeline_request_id,
                accr.release_id,r.release_version,accr.status_id,
                accr.backport_bug,(select description
                                    from aru_status_codes where status_id = accr.status_id) as descript,
                s.family_name
          from  aru_cum_codeline_requests accr,
           aru_cum_codeline_req_attrs acra,
           aru_cum_patch_releases r,
           aru_cum_patch_series s
        where accr.release_id = r.release_id
        and r.series_id     = s.series_id
        and accr.series_id = s.series_id
        and accr.backport_bug is not null
        and  acra.attribute_name = 'ADE Merged Timestamp'
        and acra.codeline_request_id = accr.codeline_request_id
        and accr.status_id in (34588, 34597, 34610)
        and accr.status_id not in (96302,34583,96371)
        and accr.series_id = $src_series_id
        and acra.attribute_value is not null
        and accr.base_bug in (
             select abbr.related_bug_number as bug
             from   aru_bugfix_bug_relationships abbr,
                    isd_bugdb_bugs ibb
             where  abbr.related_bug_number = ibb.bug_number and
                    abbr.relation_type in (609,610,613 )and
                    abbr.bugfix_id = (select bugfix_id
                           from ARU_BUGFIXES
                           where BUGFIX_RPTNO=$patch
                            and release_id = $base_rel_id
                            and rownum=1))
        and accr.base_bug not in (
                 select cr1.base_bug
                 from   aru_cum_codeline_requests cr1,
                        aru_cum_patch_series s1,
                        aru_cum_patch_series_params p1
                 where  cr1.series_id = s1.series_id
                 and    p1.series_id  = s1.series_id
                 and    p1.parameter_name = 'COMPONENT'
                 and    upper(p1.parameter_value) ='".$comp."'
                 and    s1.base_release_id = $base_rel_id
                 and    s1.product_id  = $aru_prod_id
                 and    s1.product_name like '%".$ser_starts_with."%'
                 and    s1.series_id not in ($src_series_id,$series_id)
                 and    s1.patch_type in ($prv_patch_types)
                 and    cr1.base_bug in (
                     select abbr.related_bug_number as bug
                     from   aru_bugfix_bug_relationships abbr,
                            isd_bugdb_bugs ibb
                     where  abbr.related_bug_number = ibb.bug_number and
                            abbr.relation_type in (609,610,613 )and
                            abbr.bugfix_id = (select bugfix_id
                                              from ARU_BUGFIXES
                                              where BUGFIX_RPTNO=$patch
                                              and release_id = $base_rel_id
                                              and rownum=1)

                 )
                and  cr1.status_id in (34588,34581,34583,34597,34610,34598,34599,96371)
            )";

  if($ser_starts_with =~ m/Exa/gi){
    $sql = "select distinct accr.base_bug,accr.codeline_request_id,
                accr.release_id,r.release_version,accr.status_id,
                accr.backport_bug,(select description
                                    from aru_status_codes where status_id = accr.status_id) as descript,
                s.family_name
          from  aru_cum_codeline_requests accr,
           aru_cum_codeline_req_attrs acra,
           aru_cum_patch_releases r,
           aru_cum_patch_series s
        where accr.release_id = r.release_id
        and r.series_id     = s.series_id
        and accr.series_id = s.series_id
        and accr.backport_bug is not null
        and  acra.attribute_name = 'ADE Merged Timestamp'
        and acra.codeline_request_id = accr.codeline_request_id
        and accr.status_id in (34588, 34597, 34610)
        and accr.status_id not in (96302,34583,96371)
        and accr.series_id = $src_series_id
        and acra.attribute_value is not null";

  }
 my @query_result = ARUDB::dynamic_query($sql);
 my $totalDelta = scalar(@query_result);
 add_abs_log_info($abs_req_id,96455,"Total Delta Content:$totalDelta");
=pod
 my $prev_sql = "select codeline_request_id
                 from   aru_cum_codeline_requests
                 where codeline_request_id not in(select codeline_request_id
                 from   ($sql))
                 and   series_id = $src_series_id";
=cut

    $sql = "select r.release_version,s.family_name
            from   aru_cum_patch_releases r,
                   aru_cum_patch_series s
            where r.series_id = s.series_id
            and  r.release_id = $release_id";
 my @result =  ARUDB::dynamic_query($sql);
 my $dest_rel_version = $result[0]->[0];
 my $dest_family      = $result[0]->[0];
 my $det_version      = ARUDB::exec_sf('aru_cumulative_request.get_version',$dest_rel_version);
 if(scalar @query_result > 0){
         my $i = 0;
       foreach my $request (@query_result)
        {
           my $base_bug    = $request->[0];
           my $request_id  = $request->[1];
           my $src_rel_id  = $request->[2];
           my $src_rel_version = $request->[3];
           my $status_id   =   $request->[4];
           my $backport    = $request->[5];
           my $status_decription = $request->[6];
           my $fmaily_name  = $request->[7];
           my $version      = ARUDB::exec_sf('aru_cumulative_request.get_version',$src_rel_version);
           my $tracking_grp = $fmaily_name.' '.$version.' '.$status_decription;
           my $dest_tracking_grp = $dest_family.' '.$det_version.' '.$status_decription;
             my ($cr,$err ) = ARUDB::exec_sf('aru_cumulative_request.get_request_id',$base_bug,$series_id);
                $i = $i+1;
       add_abs_log_info($abs_req_id,96455,"$i)Creating Content Request for the Bug#$base_bug");

             if($cr){
                  $err = ARUDB::exec_sp(
                            'aru_cumulative_request.update_cum_codeline_requests',
                            $cr,'status_id',$status_id);
                  $err = ARUDB::exec_sp(
                            'aru_cumulative_request.update_cum_codeline_requests',
                            $cr,'release_id',$release_id) if(!$err);
                  $err = ARUDB::exec_sp(
                            'aru_cumulative_request.update_cum_codeline_requests',
                            $cr,'backport_bug',$backport) if(!$err && $backport);
                  my @params = (
                                {name => "pn_codeline_request_id",
                                 data => $cr
                                },
                                {name => "pn_request_status",
                                 data => $status_id
                                },
                                {name => "pn_release_id",
                                 data => $release_id
                                },
                                {name => "pn_user_id",
                                 data => $user_id
                                }

                               );
                   $err = ARUDB::exec_sp('aru_cumulative_request.update_request_status', @params)if(!$err);
                   $err = ARUDB::exec_sp('aru_cumulative_request.add_request_attributes',
                                         $request_id,'CI BACKPORT BUG',$backport) if(!$err && $backport);
                   $err =  ARUDB::exec_sp(
                            'aru_cumulative_request.update_cum_codeline_requests',
                            $request_id,'status_id','96302') if(!$err);
                   @params = (
                                {name => "pn_codeline_request_id",
                                 data => $request_id
                                },
                                {name => "pn_request_status",
                                 data => 96302
                                },
                                {name => "pn_user_id",
                                 data => $user_id
                                }

                               );
                   $err = ARUDB::exec_sp('aru_cumulative_request.update_request_status', @params)if(!$err);

                    @params   =  ({name => "pn_codeline_request_id",
                                   data => $cr},
                                   {name => "pn_ci_no" ,
                                   data => $backport},
                                   {name => "pn_release_id",
                                   data => $release_id
                                   }
                                  );
                     $err =  ARUDB::exec_sp
                               ('aru_cumulative_request.change_ci_release_version',
                                @params) if($backport && !$err);
                 eval{
                     $self->change_ci_abstract($backport,$release_id) if($backport);
                     $self->copy_cr_attr($request_id,$cr);
                    };

             }else{
                my @params  = (
                                {name => "pn_base_bug",
                                 data => $base_bug
                                },
                                {name => "pn_release_id",
                                 data => $release_id
                                },
                                {name => "pn_series_id",
                                 data => $series_id
                                },
                                {name => "pn_status_id",
                                 data => $status_id
                                },
                                {name => "pv_customer",
                                 data => "INTERNAL"
                                },
                                {name => "pv_request_reason",
                                 data => "Bootstrpped from $src_rel_version"
                                }

                              );
                  ($cr,$err) = ARUDB::exec_sf
                               ('aru_cumulative_request.insert_codeline_request',
                                @params);

                  $err =  ARUDB::exec_sp('aru_cumulative_request.add_request_attributes',
                                         $cr,'Request Origin','Patch Bootstrap'
                                        ) if($cr && !$err);
                  $err = ARUDB::exec_sp(
                            'aru_cumulative_request.update_cum_codeline_requests',
                            $cr,'backport_bug',$backport) if(!$err && $backport);
                  @params = (
                                {name => "pn_codeline_request_id",
                                 data => $cr
                                },
                                {name => "pn_request_status",
                                 data => $status_id
                                },
                                {name => "pn_release_id",
                                 data => $release_id
                                },
                                {name => "pn_user_id",
                                 data => $user_id
                                }

                               );
                   $err = ARUDB::exec_sp('aru_cumulative_request.update_request_status', @params)if(!$err);
    add_abs_log_info($abs_req_id,96455,"Content Request#$cr created for the Bug $base_bug") if(!$err);
   add_abs_log_info($abs_req_id,96455,"Errorn in creating CR for  the Bug $base_bug,$err") if($err);
                   $err = ARUDB::exec_sp('aru_cumulative_request.add_request_attributes',
                                         $request_id,'CI BACKPORT BUG',$backport) if(!$err);
                   $err =  ARUDB::exec_sp(
                            'aru_cumulative_request.update_cum_codeline_requests',
                            $request_id,'status_id','96302') if(!$err);

                   @params = (
                                {name => "pn_codeline_request_id",
                                 data => $request_id
                                },
                                {name => "pn_request_status",
                                 data => 96302
                                },
                                {name => "pn_user_id",
                                 data => $user_id
                                }

                               );
                   $err = ARUDB::exec_sp('aru_cumulative_request.update_request_status', @params)if(!$err);

 add_abs_log_info($abs_req_id,96455,"Dev RU content request #$request_id status changed to Branched.") if(!$err);
    add_abs_log_info($abs_req_id,96455,"Error in moving DEV RU Content Bug $base_bug status to Branched.") if($err);


                   @params   =  ({name => "pn_codeline_request_id",
                                  data => $cr
                                 },
                                 {name => "pn_ci_no" ,
                                  data => $backport
                                 },
                                 {name => "pn_release_id",
                                  data => $release_id
                                 }
                                );
                   $err     =  ARUDB::exec_sp
                               ('aru_cumulative_request.change_ci_release_version',
                                @params) if($backport && !$err);
                  eval{
                   $self->update_base_bug($cr);


                   $self->change_ci_abstract($backport,$release_id) if($backport);
                   $self->copy_cr_attr($request_id,$cr);
                 };
             }

#
  my $finish_ci_automation = 'N';
eval{
  if(ConfigLoader::runtime('development') or
       ConfigLoader::runtime('demo')){
           $finish_ci_automation = ARUDB::exec_sf(
                               'aru_parameter.get_parameter_dev_value',
                               'COMPLETE_BACKPORT_4_BRANCHED_CI');
   }elsif(ConfigLoader::runtime("production")){
           $finish_ci_automation = ARUDB::exec_sf(
                               'aru_parameter.get_parameter_value',
                               'COMPLETE_BACKPORT_4_BRANCHED_CI');
   }
   if($finish_ci_automation eq 'Y' && $backport){
    my $txn_name =  ARUDB::exec_sf('aru_cumulative_request.get_blr_txn',
              $backport);
        if($txn_name && $txn_name ne 'NO_TXN'){
            my $error = ARUDB::exec_sp('aru_ade_api.backport_completed',
                                       'ARU',$backport,$txn_name);
        }
   }
};


        }
    add_abs_log_info($abs_req_id,96455,"Delta Content Bootstrap completed.")


 }
eval{
    $self->process_open_cis($src_series_id,$patch,$base_rel_id);
};

}

sub process_open_cis{
    my($self,$source_series_id,$patch,$base_rel_id) = @_;
    my $abs_req_id = $self->{'abs_req_id'};
    add_abs_log_info($abs_req_id,96458,"Updating the Next Release cycle contnet...");
    my $sql = "select cr.codeline_request_id,cr.release_id
                    , cr.series_id,cr.backport_bug
                    , cr.base_bug
               from aru_cum_codeline_requests cr,
                    aru_cum_patch_series acps,
                    bugdb_rpthead_v br
             where  acps.series_id =cr.series_id
             and    cr.series_id = $source_series_id
             and    cr.backport_bug is not null
             and    cr.release_id is not null
             and    br.rptno = cr.backport_bug
             and    br.status in (11,51,35)
             and    cr.status_id in (34581,34588)
             and    acps.patch_type = 96021
             and    cr.base_bug not in (
                select abbr.related_bug_number as bug
                from   aru_bugfix_bug_relationships abbr,
                       isd_bugdb_bugs ibb
                where  abbr.related_bug_number = ibb.bug_number and
                       abbr.relation_type in (609,610,613 )and
                       abbr.bugfix_id = (select bugfix_id
                                         from ARU_BUGFIXES
                                         where BUGFIX_RPTNO= $patch
                                         and release_id = $base_rel_id
                                         and rownum=1)

                )
            ";
      my @res =  ARUDB::dynamic_query($sql);
      my $nextRelcycleCount = scalar @res;
       add_abs_log_info($abs_req_id,96458,"Total Next Release Cycle content:$nextRelcycleCount");
      for my $row(@res){
          my $request_id = $row->[0];
          my $rel_id     = $row->[1];
          my $series_id  = $row->[2];
          my $ci_bug     = $row->[3];
          my $is_ru_dev =
          ARUDB::exec_sf_boolean('aru_cumulative_request.is_dev_ru',$rel_id);
          my $ru_release_id;
           my @params= (
                     {name => 'pn_codeline_request_id' ,
                      data=> $request_id},
                     {name => 'pno_rel_id',
                     data => \$ru_release_id}

              );

          my $is_rel_content =
          ARUDB::exec_sf_boolean('aru_cumulative_request.is_rel_branch_content',@params);
          if($is_ru_dev && !$is_rel_content){

          add_abs_log_info($abs_req_id,96458,"CI Bug#$ci_bug is prefixed with Next Release cycle");
              $self->change_ci_abstract($ci_bug,$rel_id,$request_id,$series_id);
          }
      }




}


sub change_ci_abstract{
 my ($self,$ci_bug,$release_id,$request_id,$series_id) = @_;
 my $sql = "select status,base_rptno
            from   bugdb_rpthead_v
            where  rptno = $ci_bug";
 my @res =  ARUDB::dynamic_query($sql);
 my $status = $res[0]->[0];
 my $base_bug = $res[0]->[1];
    $sql  = "select acpr.release_version,acps.base_release_id
             from   aru_cum_patch_releases acpr,
                    aru_cum_patch_series acps
             where  acpr.release_id = $release_id
             and    acps.series_id = acpr.series_id";
    @res  = ARUDB::dynamic_query($sql);
 my $rel_version = $res[0]->[0];
 my $base_rel_id = $res[0]->[1];
 my $sub_version = ARUDB::exec_sf('aru_backport_request.get_release_name'
                           ,$rel_version);
 my $is_nrm = ARUDB::exec_sf_boolean
                              ('aru_cumulative_request.is_new_release_model',
                              $base_rel_id);
 my $subject = 'CI BACKPORT OF BUG '.$base_bug.' FOR INCLUSION IN '.$sub_version;
 if($is_nrm){
     $subject = 'CONTENT INCLUSION OF '.$base_bug.' IN '.$sub_version;
  }
 my $is_ru_dev =
 ARUDB::exec_sf_boolean('aru_cumulative_request.is_dev_ru',$release_id);
 my $ru_release_id;
 my @params= (
                   {name => 'pn_codeline_request_id' ,
                    data=> $request_id},
                   {name => 'pno_rel_id',
                   data => \$ru_release_id}

            );

 my $is_rel_content =
 ARUDB::exec_sf_boolean('aru_cumulative_request.is_rel_branch_content',@params);
 my $rel_cycle =
 ARUDB::exec_sf('aru_cumulative_request.get_rel_cycle',$series_id);
            if($is_ru_dev && !$is_rel_content){
                 if($rel_cycle){
                      $subject = $rel_cycle.' '.$subject;
                 }

            }

 if($status < 20){
    $rel_version = '';
 }
  @params = (
                {name => 'pn_bug_number',
                 data =>  $ci_bug
                },
                {name => 'pn_status',
                 data => $status
                },
                {
                 name => 'pv_version_fixed',
                 data => $rel_version
                },
                {name => 'pv_abstract',
                 data => $subject
                }
               );
   my $err = ARUDB::exec_sp('bugdb.update_bug',@params);

}
sub copy_cr_attr{
  my($self,$src_cr,$dest_cr) = @_;
 if($src_cr && $dest_cr){
    my @params = (
                {name => 'pn_old_codeline_request_id',
                 data =>  $src_cr
                },
                {name => 'pn_new_codeline_request_id',
                 data => $dest_cr
                }
               );
   my $err = ARUDB::exec_sp('aru_cumulative_request.copy_cr_attributes',@params)
  }
}
sub update_base_bug{

my ($self,$cr) = @_;
my $sql = "select accr.base_bug,acs.series_name
           from  aru_cum_codeline_requests accr,
                 aru_cum_patch_series acs
           where accr.codeline_request_id = $cr
           and   accr.series_id = acs.series_id";
my @res = ARUDB::dynamic_query($sql);
my $base_bug = $res[0]->[0];
my $series_name = $res[0]->[1];

my $lv_view_link = ARUDB::exec_sf('aru_backport_request.get_request_view_link'
                                  ,"/ARU/CIView/process_form?rids=$cr");
my @params = (
                {name => 'p_rptno' ,
                 data => $base_bug
                },
                {name => 'p_text' ,
                 data => "@ To view the CPM request created, refer to @ $lv_view_link"
                }
                );
my $error = ARUDB::exec_sp('aru_backport_util.add_bug_text',
                            @params);

   @params = (
                {name => 'p_rptno' ,
                 data => $base_bug
                },
                {name => 'p_text' ,
                 data => "@ Series name: $series_name"
                }
              );
   $error = ARUDB::exec_sp('aru_backport_util.add_bug_text',
                            @params) if(!$error);

}
sub remove_bug_tag{
  my($self,$cgi,$bug_tag,$new_requests,$old_requests,$sql) = @_;

   my $query = "select distinct rptno
                from ARU.BUGDB_RPTBODY_V
                where upper(comments) like '%".uc($bug_tag)."%'";
   my @results = ARUDB::dynamic_query($query);
    foreach my $row(@results){
         my $bug = $row->[0];
         my $old_tags = ARUDB::exec_sf('aru.bugdb.query_bug_tag',$bug);
            $old_tags =~ s/,/ /g;
            $old_tags =~ s/\s+/ /g;

          if($old_tags !~ /$bug_tag/gi){
              next;
            }

         my $tags = $old_tags;
         my $pattern ='(^|\s*|,)'.$bug_tag.'[\s*|,]?';
            $tags =~ s/$pattern/ /ig;
        if($old_tags ne $tags){
              $tags =~ s/\s+/ /g;
         my $error_message = ARUDB::exec_sf("bugdb.create_or_replace_bug_tag",$bug,$tags);
         my $new_tags = ARUDB::exec_sf('aru.bugdb.query_bug_tag',$bug);
          if($bug_tag =~ m/onprem:R/ig || $bug_tag =~ m/saas:R/ig){
                 my $nextPlanTag = $self->next_plan_tag($bug_tag,$bug,$sql);
         if($nextPlanTag){
           if($new_tags =~ m/$nextPlanTag/ig){
               next;
             }else{
                 my $error = ARUDB::exec_sp('aru_cumulative_request.update_eta_tag',$bug,$nextPlanTag,1);
             }
            }

           }

        }


    }

}

sub add_tag_to_non_delta_bug{
my ($self,$cgi,$tag,$delta_requests,$old_requests,$sql) = @_;
  my $query = "select distinct (abbr.related_bug_number)
                  from aru_bugfix_bug_relationships abbr,
                       aru_bugfix_relationships abr,
                       aru_bugfix_requests ab
                  where abbr.bugfix_id = abr.related_bugfix_id
                  and abr.relation_type = 696
                  and abbr.relation_type in (609,610)
                  and ab.bugfix_id = abr.bugfix_id
                  and ab.bugfix_id in (
                      select distinct bugfix_id
                      from   aru_cum_codeline_requests
                      where  codeline_request_id in ($delta_requests)
                  ) union
            select distinct (abbr.related_bug_number)
            from aru_bugfix_bug_relationships abbr
            where abbr.bugfix_id in (
                   select distinct bugfix_id
                   from aru_cum_codeline_requests
                   where codeline_request_id in ($delta_requests)
                   )
                   and abbr.relation_type in (609,610)";
  if($old_requests){
         $query = '('.$query. ') union'. "(select distinct (abbr.related_bug_number)
                  from aru_bugfix_bug_relationships abbr,
                       aru_bugfix_relationships abr,
                       aru_bugfix_requests ab
                  where abbr.bugfix_id = abr.related_bugfix_id
                  and abr.relation_type = 696
                  and abbr.relation_type in (609,610)
                  and ab.bugfix_id = abr.bugfix_id
                  and ab.bugfix_id in (
                      select distinct bugfix_id
                      from   aru_cum_codeline_requests
                      where  codeline_request_id in ($old_requests)
                  ) union
            select distinct (abbr.related_bug_number)
            from aru_bugfix_bug_relationships abbr
            where abbr.bugfix_id in (
                   select distinct bugfix_id
                   from aru_cum_codeline_requests
                   where codeline_request_id in ($old_requests)
                   )
                   and abbr.relation_type in (609,610))";
  }
   $query = "select related_bug_number from(".$query.") minus"."(".$sql.")";
       my @results = ARUDB::dynamic_query($query);
           for my $row (@results){
             my $bug = $row->[0];
             my $bug_tags =  ARUDB::exec_sf('aru.bugdb.query_bug_tag',$bug);
              if($tag =~ m/onprem:R|saas:R/ig){
                 my $nextPlanTag = $self->next_plan_tag($tag);
             if($nextPlanTag){
             if($bug_tags =~ m/$nextPlanTag/ig){
               next;
             }else{
                 my $error = ARUDB::exec_sp('aru_cumulative_request.update_eta_tag',$bug,$nextPlanTag,1);
             }
             }
             }

           }


}
sub next_plan_tag{
   my($self,$tag,$bug,$sql) =@_;

     my $query = "select related_bug_number
                  from ($sql)
                  where related_bug_number = $bug";
    my @results = ARUDB::dynamic_query($query);
       if(@results){
           return 0;
        }

    if($tag =~ m/saas:R(\d+)(.)*-(\d{4})-(\d{2})-RC(\d)+/ig){
         my $eta_month = $4;
         my $eta_year  = $3;
         if($eta_month <= 11)
         {
             $eta_month = sprintf("%02d",$eta_month + 1);
         }
         else
         {
             $eta_month = sprintf("%02d",1);
             $eta_year = $eta_year + 1;
         }
         my $tmp = $eta_year.'-'.$eta_month;
         $tag =~ s/\d{4}-\d{2}/$tmp/gi;
         return $tag;

    }elsif($tag =~ m/onprem:R(\d+)(.)*-(\d{4})-(\d{2})-RC(\d)+/ig){
         my $eta_month = $4;
         my $eta_year  = $3;
         if($eta_month <= 10)
         {
             $eta_month = sprintf("%02d",$eta_month + 2);
         }
         elsif($eta_month == 11)
         {
             $eta_month = sprintf("%02d",1);
             $eta_year = $eta_year + 1;
         }
         else
         {
             $eta_month = sprintf("%02d",2);
             $eta_year = $eta_year + 1;
         }
         my $tmp = $eta_year.'-'.$eta_month;
         $tag =~ s/\d{4}-\d{2}/$tmp/gi;
         return $tag;
    }else{
           return 0;
    }
}

sub get_release_version{
    my ($self,$series_base_version,$series_id,$build_date) =@_;
    my @version = split('\.',$series_base_version);
    my $third_part = $version[2];
    my $sql = "select series_name,patch_type
               from   aru_cum_patch_series
               where  series_id= $series_id";
    my ($result) = ARUDB::dynamic_query($sql);
    my $series_name = $result->[0];
    my $patch_type  = $result->[1];
       $sql = "select count(1)
               from   aru_cum_patch_releases
               where  series_id = $series_id
               and    status_id = 34524
               and    to_char(tracking_bug) in (
                          select distinct acprp.parameter_value
                          from   aru_cum_patch_release_params acprp,
                                 aru_cum_patch_releases acpr
                          where  acprp.parameter_type = 34593
                          and    acpr.release_id = acprp.release_id
                          and    acpr.series_id  = $series_id
                          and    acprp.parameter_value is not null

               )";
       ($result) = ARUDB::dynamic_query($sql);
    my $released_count = $result->[0];
    if($patch_type == 96022 && $version[0] >= 18 ){
           if($released_count == 0){
              $third_part = 1;
           }else{
              $third_part = $released_count + 1;
           }

     $version[2] = $third_part;

   $series_base_version = join('.',@version);
    }
   return  $series_base_version.".".$build_date;

}
sub log_fast_branch_setup
{
    my ($logger, $source_series,$dest_sereis,$patch,
            $status, $timestamp,$end_of_file) = @_;

    my $file_name = $timestamp;
    my $create_file = 0;


    unless(-e  FAST_BRANCH_DIR."/$patch".
           "/$file_name".".idx")
    {
        $create_file = 1;
        unless(-e FAST_BRANCH_DIR."/$patch")
        {
            my $system   = new DoSystemCmd ( );
            $system->set_filehandle(undef);
            $system->do_mkdir(FAST_BRANCH_DIR.
                              "/$patch", 0775);
        }
    }
   if($end_of_file == -1) # Create required files in the first call
    {
        #
        # Add info to the .info file
        #
        my $infoFile= FAST_BRANCH_DIR."/$patch".
            "/$file_name".".info";
        open(FOUT,">>$infoFile") || die("Cannot Open File $infoFile");

        print FOUT "Source Series:$source_series ,Destination Series:$dest_sereis,Source Patch:$patch\n";
        print FOUT "Title Log for\n";
        print FOUT "Initiator ARU\n";
        close FOUT;
        $logger->{log} = new Log(
                                 filename     =>
                                 FAST_BRANCH_DIR."/$patch".
                                 "/$file_name.log",
                                 idxname  => "$file_name",
                                 mode     => "w",
                                 summary  => "on",
                                 markup => "on"
                                );
        $logger->{log}->print_header("ARU Setup for the Series: $dest_sereis");

        $logger->{log}->
        print("=======================================".
                        "================================================\n");
    }

    if($end_of_file == 1) # Close the file handlers in the last call
    {
        $logger->{log}->print($status);
        $logger->{log}->close();
        return;
    }
    if($status ne"") # Print the results in the log file
    {

        $logger->{log}->printf($status);
        $logger->{log}->print("\n\n");
    }

}

sub gap_process{
  my($self,$cgi,$req) = @_;
  my $content_request_id = $cgi->param('request_id');
  my $error;
  my $response;
  use ARUForms::BackportCLIUpdate;
   if($content_request_id !~ /^\d+$/ig){
         $error = "In valid Content Request#$content_request_id";
         $response = "Failed";
         goto LABEL;
   }

     eval{
           #The following  subroutine handles gap b/w the RU/RUR/CEU/ID for manadatory content
           #i.e regression,security,RUR,CEU,cloud service and RU release branch contnet
           #with in the same base release
           ARUForms::BackportCLIUpdate->patch_gap_processing($cgi,$content_request_id);
           #The following subroutine handles the gap b/w the PSU and BP with in the
           #same base release (Follow on contnet)
           #This subroutine also handles the gap b/w the RU/BP across the releases
           #i.e cross rlease gap management
           ARUForms::BackportCLIUpdate->process_gap_across_rels($content_request_id);
           1;
        }or
        do{
            my $err = $@;
               $err =~ s/"/'/gi;
            $error = "Error in gap processing for CR #$content_request_id"."Error:$err";
            $response = 'Failed';
            goto LABEL;
        };
      $error ="";
      $response ="Success";
      goto LABEL;
LABEL:
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error"
         }
JSON_RET

 $error = ARUDB::exec_sp('aru_cumulative_request.add_request_attributes',$content_request_id,'gap_process_status',$ret_json);

  # print STDOUT $cgi->header("Content-Type: text/json");
    $self->send_cgi_header($req);
    print STDOUT $ret_json;
}

sub automate_branch_setup{
    my($self,$cgi,$req) = @_;
    my $source_series   = $cgi->param('source_series');
    my $dest_patch_type = $cgi->param('dest_patch_type');
    my $dest_version    = $cgi->param('dest_version');
    my $src_tracking_bug= $cgi->param('src_tracking_bug');
    my $src_label       = $cgi->param('src_label');
    my $dest_label      = $cgi->param('dest_label');
    my $comp_ser_label  = $cgi->param('comp_ser_label');
    my $dest_branch     = $cgi->param('dest_branch');
    my $destination_series = $cgi->param('destination_series');
    my $dest_rel_version   = $cgi->param('rel_version');
    my $user_name          = $cgi->param('username');
    my $need_stream_rel    = $cgi->param('is_stream');
    my $create_gi_series_rel    = $cgi->param('create_gi');
    my $error;
    my $response;
    my $dest_series;
    my $dest_stream_release;
    my $json_decoded = '';
    my @src_series_info;
    my $src_patch_type;
    my $src_prod_id;
    my $src_family_name;
    my $base_rel_id;
    my $series_id;
    my $created_from;
    my $patch_desc;
    my $patch_type;
    my $dest_family_name;
    my $dest_series_product;
    my $src_prod_name;
    my $dest_series_id;
    my $dest_rel_id;
    my $src_rel_id;
    my $label_date;
    my $is_src_stream;
    my $abs_req_id;
    my @input_cgi_params = $cgi->param;
    my %inputParams;
    my $log_err;
       for(@input_cgi_params){
            $inputParams{$_} = $cgi->param($_);
       }
    my $inputCGIString = 'Inputs->'.Dumper(\%inputParams);
    my $patch_descriptions = { 'BP'  => 'Bundle Patch'
                              ,'PSU' => 'Patch Set Update'
                              ,'SPU' => 'Security Patch Update'
                              ,'SP'  => 'System Patch'
                              ,'RUE' => 'Release Update Extension'
                              ,'RU'  => 'Release Update'
                              ,'RUR' => 'Release Update Revision'
                              ,'CEU' => 'Cloud Emergency Update',
                              ,'RUI' => 'Release Update Increment'
                              ,'ID'  => 'Interim Drop'
                             };

    my $patch_name_to_ids  = { 'BP'  => 34501
                              ,'PSU' => 34502
                              ,'SPU' => 34503
                              ,'SP'  => 35350
                              ,'RU'  => 96021
                              ,'RUR' => 96022
                              ,'CEU' => 96023
                              ,'RUE' => 96084
                              ,'RUI' => 96085
                              ,'ID'  => 96085
                             };

     if($ENV{REQUEST_METHOD} eq 'POST'){
       if($cgi->param('POSTDATA')){
          my $postdata = $cgi->param('POSTDATA');
              eval{
                $json_decoded = decode_json($postdata);
                 1;
                }or
                do{
          $error = 'Not a valid JSON input.';
          $response = 'Failed';
                goto LABEL;
                };

          $source_series   =  $json_decoded->{'source_series'};
          $dest_patch_type =  $json_decoded->{'dest_patch_type'};
          $dest_version    =  $json_decoded->{'dest_version'};
          $src_tracking_bug = $json_decoded->{'src_tracking_bug'};
          $src_label  = $json_decoded->{'src_label'};
          $dest_label = $json_decoded->{'dest_label'};
          $comp_ser_label = $json_decoded->{'comp_ser_label'};
          $dest_branch = $json_decoded->{'dest_branch'};
          $destination_series  = $json_decoded->{'destination_series'};
          $dest_rel_version = $json_decoded->{'rel_version'};
          $need_stream_rel  = $json_decoded->{'is_stream'};
          $user_name        =  $json_decoded->{'username'};
           $inputCGIString = 'Inputs->'.Dumper($json_decoded);

         }

        }
    my $ade_src_label = $src_label;
    my $user_id;
       if(!$user_name){

        $user_id = 1;

       }else{

         my $sql = "select user_id
                   from   aru_users
                   where  upper(user_name)=upper('".$user_name."')";
         my  @res =  ARUDB::dynamic_query($sql);
             $user_id = $res[0]->[0];

       }
     if(!$user_id){
          $user_id = 1;
      }
    my @abs_req_params = (
                     {name => 'pn_user_id' ,
                      data => $user_id
                     },
                     {name => 'pno_request_id' ,
                      data => \$abs_req_id}

                    );
     $error = ARUDB::exec_sp('aru_cumulative_request.create_abs_request',
                               @abs_req_params);
      if($abs_req_id){
            $error = ARUDB::exec_sp('aru_cumulative_request.add_abs_inputs'
                                  ,$abs_req_id,$inputCGIString);
      }
      $self->{'abs_req_id'} = $abs_req_id;

     if(!$source_series){
        $response = 'Failed';
        $error    = 'Invalid Source Series.';
        goto LABEL;

      }
     add_abs_log_info($abs_req_id,96450,'Validating the Source Series...');
     add_abs_log_info($abs_req_id,96450,"Source Series : $source_series");
     if(!$self->is_valid_series($source_series)){
          $response = 'Failed';
          $error    = 'Invalid Source Series.';
          add_abs_log_info($abs_req_id,96450,$error.':'.$source_series);
          goto LABEL;

      }

                #
                #       Fetching Source Series Info
                #
      add_abs_log_info($abs_req_id,96450,
                       $error.'Collecting Source Series Info...');
      @src_series_info = $self->get_series_info($source_series);
      $series_id = $src_series_info[0]->[0];
      $src_patch_type = $src_series_info[0]->[1];
      $src_prod_id = $src_series_info[0]->[2];
      $src_family_name = $src_series_info[0]->[3];
      $base_rel_id = $src_series_info[0]->[4];
      $src_prod_name = $src_series_info[0]->[5];
      $is_src_stream = ARUDB::exec_sf(
                            'aru_cumulative_request.get_stream_release_id',
                            $series_id);
  #
  #if the base release version is greater than or equal to 18.0.0.0.0
  #is called new release model
  #
    my  $is_new_rel_model = ARUDB::exec_sf_boolean(
                             'aru_cumulative_request.is_new_release_model'
                            ,$base_rel_id);
        if(!$destination_series){

            $response = 'Failed';
            $error    = 'Destination Series Name is needed.';
            goto LABEL;

        }
    add_abs_log_info($abs_req_id,96450,
                      'Validating the Destination Series Patch Type...');
    if($destination_series){

             my $x = $destination_series;

             if($x !~ /Bundle Patch|Patch Set Update|Security Patch Update|System Patch|Release Update|Release Update Revision|Cloud Emergency Update|Release Update Extension|Release Update Increment|Interim Drop/gi){

        $response = 'Failed';
        $error    = 'Destination Series shoud contain valid patch description
                    Eg:Bundle Patch , Release Update.';
        add_abs_log_info($abs_req_id,96450,'Error:'.$error);
              goto LABEL;
            }

          my $y = $destination_series;
          add_abs_log_info($abs_req_id,96450,
              "Validating the destination Series Version. $destination_series");
          if( $y !~ /\s+((\d+)\.){4}(\d+)$/gi){

                $response = 'Failed';
                $error    = $destination_series.
                      ' Destination Series name should '.
                      'contain valid 5 digit version.';
                add_abs_log_info($abs_req_id,96450,'Error:'.$error);
                goto LABEL;

             }
          $dest_version = ARUDB::exec_sf(
                               'aru_cumulative_request.get_series_version',
                                $destination_series);

          if($destination_series =~ /Bundle Patch/gi){

          $patch_type = 34501;
          $patch_desc = 'Bundle Patch';
                }elsif($destination_series =~ /Patch Set Update/gi){

          $patch_type = 34502;
          $patch_desc = 'Patch Set Update';

                }elsif($destination_series =~ /Security Patch Update/gi){

          $patch_type = 34503;
          $patch_desc = 'Security Patch Update';

                }elsif($destination_series =~ /System Patch/gi){

          $patch_type = 35350;
          $patch_desc = 'System Patch';

                }elsif($destination_series =~ /Release Update Extension/gi){

          $patch_type = 96084;
          $patch_desc = 'Release Update Extension';

                }elsif($destination_series =~ /Release Update(\s){1}(((\d+)\.){2,4}(\d+))$/gi){

          $patch_type = 96021;
          $patch_desc = 'Release Update';

                }elsif($destination_series =~ /Release Update Revision/gi){

          $patch_type = 96022;
          $patch_desc = 'Release Update Revision';

                }elsif($destination_series =~ /Cloud Emergency Update/gi){

          $patch_type = 96023;
          $patch_desc = 'Cloud Emergency Update';

                }elsif($destination_series =~ /Release Update Increment/gi){

          $patch_type = 96085;
          $patch_desc = 'Release Update Increment';

                }elsif($destination_series =~ /Interim Drop/gi){

          $patch_type = 96085;
          $patch_desc = 'Interim Drop';

                }

          $dest_series_product = $self->get_series_product($destination_series
                                                        ,$patch_desc
                                                        ,$dest_version
                                                        );
       my $temp = $dest_series_product;
          $temp =~ s/\s+//gi;
          $temp =~ s/Database/DB/gi if($temp =~ /Database/gi);
          $temp =~ s/Exadata/Exa/gi if($temp =~ /Exadata/gi);
          $temp =~ s/For//gi;

       my $pt = join '', map {uc substr $_, 0, 1} split ' ', $patch_desc;
          $temp = $temp.$pt;

          $dest_family_name = uc($temp);


        add_abs_log_info($abs_req_id,96451,
                         'Checking Destination Series existence..');

        my $sql ="select series_id
                  from   aru_cum_patch_series
                  where  series_name='".$destination_series."'";

        my @result = ARUDB::dynamic_query($sql);
           $dest_series_id = $result[0]->[0];
        add_abs_log_info($abs_req_id,96451,
             "Destination Series:$destination_series already exists")
        if($dest_series_id);
        }

          if(!$src_tracking_bug){

             $response = 'Failed';
             $error    = 'Tracking bug associated to source series is needed.';
             add_abs_log_info($abs_req_id,96450,
                              'Error:'.$error.':'.$source_series);
             goto LABEL;
          }

         if($src_tracking_bug){

           if($src_tracking_bug !~ /^\d+$/){

            $response = 'Failed';
            $error    = 'Error:Invalid Tracking Bug';
            add_abs_log_info($abs_req_id,96450,$error.':'.$source_series);
            goto LABEL;
            }

           if(!$self->is_ru_dev_series($source_series)
                && ($src_patch_type == 96021 ||
                      $src_patch_type == 96022 )){

            my $sql = "select release_id
                       from   aru_releases
                       where  release_id in (
                              select max(aru_release_id)
                              from   aru_cum_patch_releases
                              where  series_id = $series_id
                              and    status_id  in (34529,34524,34523,34522)
                       )";
            my @result = ARUDB::dynamic_query($sql);
            $created_from  = $result[0]->[0];
       }
      if(!$created_from){
       $created_from = $base_rel_id;
      }

      if(!$dest_series_id){
        add_abs_log_info($abs_req_id,96451,
                         "Creating the Destination Series:$destination_series");

          my $comment = "This Series is getting created from $source_series ".
                       "from fast branch setup API. using the source patch $src_tracking_bug";
        add_abs_log_info($abs_req_id,96451,$comment);
         my @params = ({name => "pn_aru_product_id",
                      data => $src_prod_id},
                     {name => "pv_family_name",
                      data => uc($dest_family_name)},
                     {name => "pv_product_name",
                      data => $dest_series_product},
                     {name => "pv_patch_type" ,
                      data => $patch_desc},
                     {name => "pv_status",
                      data => 'Active'},
                     {name => "pn_user_id",
                      data => $user_id},
                     {name => "pn_base_release_id",
                      data => $base_rel_id},
                     {name => "pv_comments" ,
                      data => $comment},
                     {name => "pno_series_id" ,
                      data => \$dest_series_id},
                     {name => "pv_new_rel_version",data=>$dest_version}
                  );
            if($dest_series_id){
            add_abs_log_info($abs_req_id,96451,"Destination Series:$destination_series Successfully Created!.");

            }
            my $err = ARUDB::exec_sp('aru_cumulative_request.create_series'
                                     ,@params
                                    );
            if($err){
                  $response = 'Failed';
                  $error = $err;
             add_abs_log_info($abs_req_id,96451,"Error in creating the Destination Series:$destination_series ,".$err);
                  goto LABEL;
                 }
          }
          if($dest_series_id){

             my $GI_series_prod = $dest_series_product;
                $GI_series_prod =~ s/^\s*\S+/GI/;
             my $GI_series = $GI_series_prod.' '.$patch_desc.' '.$dest_version;
             my @sysPatch_params = ({name => "pn_series_id",
                      data => $dest_series_id},
                     {name => "pv_attribute_name",
                      data => 'System Patch Series'},
                     {name => "pv_attribute_type",
                      data => 'LOV'},
                     {name => "pv_attribute_value" ,
                      data => $GI_series},
                     {name => "pv_attribute_default",
                      data => $GI_series},
                     {name => "pv_attribute_required",
                      data => 'N'},
                     {name => "pn_attribute_level",
                      data => '3'},
                     {name => "pn_user_id",
                      data => $user_id
                     }
                  );
         eval{
          my $err =
                  ARUDB::exec_sp('aru_cumulative_request.add_series_attributes',
                                @sysPatch_params);
          };
          if ($create_gi_series_rel)
          {
             #
             # Create GIRU and GIRUR series and release as per bug 30944385
             #
             add_abs_log_info($abs_req_id,96451,
                         "Creating the GI Series:$GI_series");
             $self->_create_gi_series_release($GI_series, $src_prod_id,
                                               $GI_series_prod,
                                               $dest_family_name,
                                               $dest_series_product,
                                               $patch_desc,
                                               $user_id,
                                               $base_rel_id,
                                               $dest_version,
                                               $dest_rel_version,
                                               $source_series,
                                               $series_id,
                                               $src_patch_type);
           }
      #
      # store the Source fast branch tracking bug details
      #
         my @params = (
                {name => "pn_series_id",
                 data => $dest_series_id
                },
                {name => "pv_parameter_name",
                 data => "Source_Fast_Branch"
                },
                {name => "pn_parameter_type",
                 data =>  96183
                },
                {name => "pv_parameter_value",
                 data =>  $src_tracking_bug
                },
                {name => "pn_user_id",
                 data => $user_id}
              );

       my $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                                ,@params);
       add_abs_log_info($abs_req_id,96451,
                        'Activating the Destination Series...');
       $err =  ARUDB::exec_sp('aru_cumulative_request.update_cum_patch_series'
                               ,$dest_series_id,'status_id',34511,$user_id);
       @params = (
                       {name => "pn_series_id",
                        data => $dest_series_id
                       },
                       {name => "pv_parameter_name",
                        data => "series_created_from"
                       },
                       {name => "pn_parameter_type",
                        data =>  96183
                       },
                       {name => "pv_parameter_value",
                        data => $created_from
                       },
                       {name => "pn_user_id",
                        data => $user_id}
                     );

         $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                               ,@params);

         add_abs_log_info($abs_req_id,96452,
                          'Fetching Content Request Products Info...');
          my $sql = "select bugdb_prod_id,component,
                            comp_criteria,sub_components,
                            sub_comp_criteria
                     from   aru_cum_content_req_prods
                     where  series_id= $series_id";

          my @results = ARUDB::dynamic_query($sql);
          add_abs_log_info($abs_req_id,96452,
                    'Adding Content Request Products to Destination Series...');
          foreach my $rec (@results){

             my $bugdb_prod_id  = $rec->[0];
             my $component      = $rec->[1];
             my $comp_criteria  = $rec->[2];
             my $sub_components = $rec->[3];
             my $sub_comp_criteria = $rec->[4];

          @params = (
                    {name => "pn_series_id",
                      data =>  $dest_series_id},
                     {name => "pn_bugdb_id",
                      data => $bugdb_prod_id
                     },
                     {name => "pv_component",
                      data => $component
                     },
                     {name => "pv_comp_criteria",
                      data => $comp_criteria
                     },
                     {name => "pv_sub_comp_list",
                      data => $sub_components
                     },
                     {name => "pv_sub_comp_criteria",
                      data => $sub_comp_criteria
                     },
                     {name => "pn_user_id",
                      data => $user_id
                     }
                    );
        eval{
         $err = ARUDB::exec_sp(
                 'aru_cumulative_request.add_content_req_products',
                  @params) if($dest_series_id);
        };
         add_abs_log_info($abs_req_id,96452,
                'Error in Adding the content request Products,'.$err) if($err);

                }
         add_abs_log_info($abs_req_id,96452,
                          'Fetching Source Series Parameters...');

         $sql = "select parameter_name,parameter_value,parameter_type
                  from   aru_cum_patch_series_params
                  where  series_id= $series_id
                  and    parameter_type not in(90035,34590,34600,34601,
                         34602,34591,34603,34604,34605,34606,34666,96183
                  )";
        @results = ARUDB::dynamic_query($sql);
        add_abs_log_info($abs_req_id,96452,
                        'Adding Parameters to Destination Series...');
        foreach my $rec (@ results){

         my $parameter_name  = $rec->[0];
         my $parameter_value = $rec->[1];
         my $parameter_type  = $rec->[2];

           if($parameter_name eq 'Series Branch Name'
              && $parameter_value){

              if($dest_branch){
                my $branch = ARUDB::exec_sf(
                       'aru_cumulative_request.get_series_parameter_value',
                        $dest_series_id,
                       'Series Branch Name');

                $parameter_value = $dest_branch;
              }
           }elsif($parameter_name eq 'Series Branch Name'
                  && !$parameter_value){

           my $branch = ARUDB::exec_sf(
                       'aru_cumulative_request.get_series_parameter_value',
                        $dest_series_id,
                       'Series Branch Name');

           if($dest_branch){
                $parameter_value = $dest_branch;
                    if($branch){
                           $parameter_value = $parameter_value.','.$branch;
                    }
               }
           }
           my @params = (
                        {       name => "pn_series_id",
                                data => $dest_series_id
                        },
                        {       name => "pv_parameter_name",
                                data => $parameter_name
                        },
                        {       name => "pn_parameter_type",
                                data => $parameter_type
                        },
                        {       name => "pv_parameter_value",
                                data => $parameter_value
                        },
                        {       name => "pn_user_id",
                                data => $user_id
                        }
                         );
           eval{
                        $err = ARUDB::exec_sp(
                        'aru_cumulative_request.add_series_parameters',
                        @params
                        ) if($dest_series_id);
                 };
            add_abs_log_info($abs_req_id,96452,
               "Error in Adding $parameter_name to Destination Series. $err")
               if($err);
                        }
          my $is_stream = 'No';

          if($need_stream_rel){
            $is_stream = 'Yes';
          }

        $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                              ,$dest_series_id
                              ,'Continuous Dated Release'
                              ,'34530'
                              ,$is_stream
                              ,$user_id
                              );
        $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                              ,$dest_series_id
                              ,'Patch Packaging'
                              ,'34530'
                              ,'Patch Factory'
                              ,$user_id
              ) if($is_stream ne 'Yes');

        @params = (
                       {name => "pn_series_id",
                        data => $dest_series_id
                       },
                       {name => "pv_parameter_name",
                        data => "series_created_from"
                       },
                       {name => "pn_parameter_type",
                        data =>  96183
                       },
                       {name => "pv_parameter_value",
                        data => $created_from
                       },
                       {name => "pn_user_id",
                        data => $user_id}
                     );

        $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                                ,@params
                 );

        $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters'
                            ,$dest_series_id
                            ,'Series Family Description'
                            ,'34530',uc($dest_family_name)
                            ,$user_id
                            ) if($dest_family_name !~ /^BI/gi  &&
                                 $dest_family_name !~ /^SOA/gi &&
                                 $dest_family_name !~ /^OAM/gi &&
                                 $dest_family_name !~ /^ADF/gi &&
                                 $dest_family_name !~ /^OIM/gi &&
                                 $dest_family_name !~ /^Web/gi);

        $sql = "select owner_type,email_address,
                       notification
                from   aru_cum_patch_series_owners
                where  series_id = $series_id";

        @results = ARUDB::dynamic_query($sql);

        foreach my $rec (@results){

            my $owner_type    = $rec->[0];
            my $email_address = $rec->[1];
            my $notification  = $rec->[2];

            @params = (
                     {     name => "pn_series_id",
                           data =>  $dest_series_id
                     },
                     {     name => "pv_owner_type",
                           data => $owner_type
                     },
                     {     name => "pv_email_address",
                           data => $email_address
                     },
                     {     name => "pv_notification" ,
                           data => $notification
                     },
                     {     name => "pn_user_id",
                           data => $user_id
                     }
                                );
                $err = ARUDB::exec_sp('aru_cumulative_request.add_series_owners'
                                      ,@params
                                     );
          }
           $sql ="select approval_level,approver_type,
                         approver_id
                  from   aru_cum_patch_series_levels
                  where  series_id = $series_id";

           @results = ARUDB::dynamic_query($sql);

           add_abs_log_info($abs_req_id,96452,"Adding Series Approval Levels");

           foreach my $rec (@results){
                        my $approval_level    = $rec->[0];
                        my $approver_type     = $rec->[1];
                        my $approver_id       = $rec->[2];

                        @params = (
                                {
                                 name => "pn_series_id",
                                 data =>  $dest_series_id
                                },
                                {
                                  name => "pn_approval_level",
                                  data => $approval_level
                                },
                                {
                                  name => "pv_approver_type",
                                  data => $approver_type
                                },
                                {
                                  name => "pn_approver_id",
                                  data => $approver_id
                                },
                                {
                                  name => "pn_user_id",
                                  data => $user_id
                                }
                     );

           eval{
             $err = ARUDB::exec_sp('aru_cumulative_request.add_series_approvals'
                                  ,@params
                                  );
           };
      add_abs_log_info($abs_req_id,96452,
                       "Error in adding the approval levels.$err") if($err);
                        }

      $sql = "select attribute_name,attribute_type,
                   attribute_value,attribute_default,
                   attribute_required,attribute_validation,
                   attribute_gap,attribute_order,
                   attribute_level,help_code
            from   aru_cum_patch_series_attrs
            where  series_id= $series_id";
      @results = ARUDB::dynamic_query($sql);
      add_abs_log_info($abs_req_id,96452,'Adding Series attributes...');
      foreach my $rec (@results){

         my $attribute_name       = $rec->[0];
         my $attribute_type       = $rec->[1];
         my $attribute_value      = $rec->[2];
         my $attribute_default    = $rec->[3];
         my $attribute_required   = $rec->[4];
         my $attribute_validation = $rec->[5];
         my $attribute_gap        = $rec->[6];
         my $attribute_order      = $rec->[7];
         my $attribute_level      = $rec->[8];
         my $help_code            = $rec->[9];
         if($attribute_name eq 'System Patch Series'){
              next;
         }
         @params = ({name => "pn_series_id",
                      data => $dest_series_id},
                     {name => "pv_attribute_name",
                      data => $attribute_name},
                     {name => "pv_attribute_type",
                      data => $attribute_type},
                     {name => "pv_attribute_value" ,
                      data => $attribute_value},
                     {name => "pv_attribute_default",
                      data => $attribute_default},
                     {name => "pv_attribute_required",
                      data => $attribute_required},
                     {name => "pv_attribute_validation",
                      data => $attribute_validation},
                     {name => "pv_attribute_gap" ,
                      data => $attribute_gap},
                     {name => "pn_attribute_order" ,
                      data => $attribute_order},
                     {name => "pn_attribute_level",
                      data=>$attribute_level},
                     { name => "pn_user_id",
                        data => $user_id
                     }
                  );
         eval{
          $err = ARUDB::exec_sp('aru_cumulative_request.add_series_attributes',
                                @params);
          };
          add_abs_log_info($abs_req_id,96452,
                         'Error in adding Series Attributes.'.$err) if($err);
          }
          if($src_tracking_bug){
             $sql ="select release_id,status_id,release_label
                     from  aru_cum_patch_releases
                    where  tracking_bug = $src_tracking_bug
                    and    series_id    = $series_id";

             @results = ARUDB::dynamic_query($sql);
                                $src_rel_id = $results[0]->[0];
             $src_label  = $results[0]->[2];
             if(!$src_rel_id){

              $sql = "select arp.release_id,arp.parameter_name,
                             arp.parameter_value
                      from   aru_cum_patch_release_params arp,
                             aru_cum_patch_releases acpr
                      where  arp.release_id = acpr.release_id
                      and    acpr.series_id = $series_id
                      and    arp.parameter_type in (34593,34617)
                      and    arp.parameter_value = $src_tracking_bug";

              @results = ARUDB::dynamic_query($sql);
              $src_rel_id = $results[0]->[0];
              $src_label  = $results[0]->[1];
              }
              if(!$src_rel_id){

                $response = 'Failed';
                $error    = "Error:Could not find the CPM release associated ".
                             "the Tracking Bug#$src_tracking_bug";
                add_abs_log_info($abs_req_id,96452,$error);
                goto LABEL;
               }
          my $lbl = ($src_label)?$src_label:$ade_src_label;
          add_abs_log_info($abs_req_id,96453,"Started Release Creation...");

          $dest_rel_id  = $self->_create_release($destination_series,
                                                $dest_rel_version,
                                                $user_id,$src_rel_id,$lbl);

          if($dest_rel_id){
              $sql  = "select status_id
                       from   aru_cum_patch_releases
                       where  release_id = $dest_rel_id";

              @results = ARUDB::dynamic_query($sql);

              if($results[0]->[0] != 34522 ){

                $err  = $self->_update_release_status($dest_rel_id,
                                                        34526,
                                                        $user_id);
		# Not moving release to codeline open, pls see bug 30453293 for
		# more details					
                #$err  = $self->_update_release_status($dest_rel_id,
                 #                                       34522,
                  #                                      $user_id);
              }
=pod
                if($need_stream_rel &&
                    ($patch_type!=96022 && $patch_type!=96023 )){
                    if($src_label){
                      $err =ARUDB::exec_sp(
                          'aru_cumulative_request.add_release_parameters',
                           $dest_rel_id,$src_label,$src_tracking_bug,34593);
                    }
                }
                if($is_src_stream && $src_label &&
                    ($patch_type!=96022 && $patch_type!=96023 )){
                      $err =ARUDB::exec_sp(
                          'aru_cumulative_request.add_release_parameters',
                           $src_rel_id,$src_label,$src_tracking_bug,34617);
                     $err =ARUDB::exec_sp(
                          'aru_cumulative_request.delete_release_parameter',
                           $src_rel_id,$src_label,34593,$user_id) if(!$need_stream_rel);
                }
=cut
   add_abs_log_info($abs_req_id,96455,"Started Bootstrapping of content..");
               $req->pool->cleanup_register(sub
                             {
                               $self->bootstrap_content(
                                          $series_id,
                                          $src_tracking_bug,
                                          $dest_series_id,
                                          $dest_rel_id,
                                          $label_date,
                                          $user_id
                                 )if($patch_type!=96022 && $patch_type!=96023);

                               $self->bootstrap_prv_patch(
                                      $series_id,
                                      $dest_series_id,
                                      $dest_rel_id,
                                      $src_tracking_bug,
                                      $user_id
                                   );


                            });
=pod
              $self->_update_patch_metadata($src_tracking_bug,
                                            $dest_rel_id,
                                            $label_date) if($patch_type!=96022
                                                         && $patch_type!=96023 && $need_stream_rel);
=cut

           }
          }
       }
       }

if($dest_series_id && $ade_src_label && $dest_label){
  my $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters',
            $dest_series_id,'Source Label Name',96183,$ade_src_label,1);
     $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters',
            $dest_series_id,'Target Label Series',96183,$dest_label,1);
     if($comp_ser_label){
        $err = ARUDB::exec_sp('aru_cumulative_request.add_series_parameters',
            $dest_series_id,'Comp Label Series',96183,$comp_ser_label,1);

     }
  $req->pool->cleanup_register(sub{
    $self->create_ade_branch($dest_series_id,$ade_src_label,$dest_label,$dest_branch,$user_id, $dest_rel_id);
});

}

LABEL:
if($error){
  $destination_series = '';
  $dest_stream_release = '';
}
my $ret_json = <<JSON_RET;
         {
           "response": "$response",
           "error": "$error",
           "destination_series" : "$destination_series",
           "destination_stream_release" : "$dest_stream_release",
           "abs_req_id" :"$abs_req_id"
         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;
}

sub create_ade_branch{
  use ConfigLoader "ISDSPF::Config" => $ENV{ISD_HOME}.'/conf/isdspf.pl';
  my ($gen_user, $gen_password)  = (ISDSPF::Config::jiraUserId,
                             ISDSPF::Config::jiraPassword);
  my ($self,$dest_series_id,$src_lbl,$dest_lbl,$dest_branch,$user_id,
  $dest_rel_id) = @_;
    my $abs_req_id = $self->{'abs_req_id'};
   add_abs_log_info($abs_req_id,96457,"Started Creating ADE Branch/Label...");

  my $mergereq_RM;
    if($dest_lbl =~ m/^HAS/gi){
         $mergereq_RM = ARUDB::exec_sf('aru_cumulative_request.get_series_parameter_value',0,'HAS_MERGE_REQ_RM');
      }elsif($dest_lbl =~ m/^USM/gi){
         $mergereq_RM = ARUDB::exec_sf('aru_cumulative_request.get_series_parameter_value',0,'USM_MERGE_REQ_RM');
      }elsif($dest_lbl =~ m/^RDBMS/gi){
         $mergereq_RM = ARUDB::exec_sf('aru_cumulative_request.get_series_parameter_value',0,'RDBMS_MERGE_REQ_RM');
      }
  my $need_ade_branch = ARUDB::exec_sf(
                         'aru_parameter.get_parameter_value',
                          'NEED_ADE_BRANCH');
  if(ConfigLoader::runtime('development') or
       ConfigLoader::runtime('demo')){
           $need_ade_branch = 'N';
   }
  #$need_ade_branch = 'Y';
  if($need_ade_branch eq 'Y'){
        use LWP::UserAgent;
        my $ua = LWP::UserAgent->new;
        my $prv_status = ARUDB::exec_sf(
                  'aru_cumulative_request.get_series_parameter_value'
                 ,$dest_series_id
                 ,$dest_lbl.'-TASK_STATUS');

        if(!$prv_status && uc($prv_status) ne 'SUCCESS' ){
        my $server_endpoint = ARUDB::exec_sf(
                                                                                                                'aru_parameter.get_parameter_value',
                            'ADE BRACNH INIT API'
                                                                                                                        );

                        my $is_for_test = ARUDB::exec_sf(
                                                                                                        'aru_parameter.get_parameter_value'
                                                                                                        ,'ADE TEST BRACNH');

                                my $task_sequence = ARUDB::exec_sf(
                                                                'aru_parameter.get_parameter_value'
                                                                ,'ADE BRACNH TASK ID');

                        my $req = HTTP::Request->new(POST => $server_endpoint);
                                        $req->authorization_basic($gen_user,$gen_password);
                                        $req->header('content-type' => 'application/json');
  #$is_for_test = 'Y';
                          if(ConfigLoader::runtime('development') or
                  ConfigLoader::runtime('demo')){
           $is_for_test = 'Y';
                                }

                my $post_data = '{ "task_sequence": "'.$task_sequence.'",
                      "params" : {"baseLabel" : "'.$src_lbl.'",
                      "newSeries" : "'.$dest_lbl.'","testOnly" : "'.$is_for_test.'","newBranchName":"'.$dest_branch.'","userName":"ARU"},"userName":"ARU" }';
                if($mergereq_RM){
                 $post_data = '{ "task_sequence": "'.$task_sequence.'",
                      "params" : {"baseLabel" : "'.$src_lbl.'",
                      "newSeries" : "'.$dest_lbl.'","testOnly" : "'.$is_for_test.'","newBranchName":"'.$dest_branch.'","mergereqRM":"'.$mergereq_RM.'","userName":"ARU"},"userName":"ARU" }';

                }
          print STDERR 'ade branch post data:'.$post_data;
                        $req->content($post_data);
                my $resp = $ua->request($req);

  if ($resp->is_success){
    my $message = $resp->decoded_content;
    my $text = decode_json($message);
    my $rsp_code = $text->{'responseCode'};
    my $event_id = $text->{'eventId'};
    my $err_msg  = $text->{'errorMessage'};
    my $err = ARUDB::exec_sp(
                     'aru_cumulative_request.add_series_parameters'
                    ,$dest_series_id
                    ,$dest_lbl.'-INIT_RESPONSE'
                    ,96183
                    ,$rsp_code,1)if($rsp_code) ;
       $err = ARUDB::exec_sp(
                   'aru_cumulative_request.add_series_parameters'
                  ,$dest_series_id
                  ,$dest_lbl.'-INIT_EVENT'
                  ,96183
                  ,$event_id
                  ,1) if($event_id);
       $err = ARUDB::exec_sp(
                   'aru_cumulative_request.add_series_parameters'
                  ,$dest_series_id
                  ,'ADE_BRANCH_EVENT_ID'
                  ,96183
                  ,$event_id
                  ,1) if($event_id);

       $err = ARUDB::exec_sp(
                'aru_cumulative_request.add_series_parameters'
                ,$dest_series_id
                                                                ,$dest_lbl.'-INIT_ERROR'
                                                          ,96183,$err_msg,1) if($err_msg);
        add_abs_log_info($abs_req_id,96457,"Successfully Submited the Request for creating ADE branch/Label");

  }else{
         my $status_line = $resp->status_line;
         my $sql = "select email_address
                          from   aru_users
                          where  user_id=$user_id";
         my @result = ARUDB::dynamic_query($sql);
         my $to_email= $result[0]->[0];

         my $err = ARUDB::exec_sp(
                'aru_cumulative_request.add_series_parameters'
                ,$dest_series_id
                ,'ADE_BRANCH_API_STATUS'
                ,96183,$status_line,1) if($status_line);
add_abs_log_info($abs_req_id,96457,"Failed to submit the request for ADE Branch/Label creation:".$resp->content);
         my $to_header  =
            {
             'Subject'      => "CPM:Error in creating ADE Branch/label for the series:$dest_lbl",
             'From'         => 'ARU CPM alert',
             'Reply-To'     =>
             'ARU Notification <'.ISD::Const::isd_do_not_reply.'>',
             'Content-type' => "text/html"
             };
        ISD::Mail::sendmail($to_email, $to_header, $resp->content);

  }

  my $event_id = ARUDB::exec_sf(
                                                                                'aru_cumulative_request.get_series_parameter_value'
                                                                        ,$dest_series_id
                                                                        ,$dest_lbl.'-INIT_EVENT');

  my $event_rsp = ARUDB::exec_sf(
                                                                        'aru_cumulative_request.get_series_parameter_value'
                                                                        ,$dest_series_id
                                                                        ,$dest_lbl.'-INIT_RESPONSE');

                if($event_rsp == 200 && $event_id ){

                        $server_endpoint =  ARUDB::exec_sf(
                                                                                                                'aru_parameter.get_parameter_value'
                                                                                                        ,'ADE BRACNH SET UP  API');

        my $spare_branch_task = ARUDB::exec_sf(
                                                                                                        'aru_parameter.get_parameter_value'
                                                                                                        ,'ADE SPARE BRACNH TASK ID');

      $server_endpoint = $server_endpoint.$event_id.'/task/'.$spare_branch_task;
      $req = HTTP::Request->new(GET => $server_endpoint);
      $req->authorization_basic($gen_user,$gen_password);
      $req->header('content-type' => 'application/json');
      $resp = $ua->request($req);
      if($resp->is_success){
         my $message = $resp->decoded_content;
         my $text = decode_json($message);
         my $status = $text->{'status'};
         my $log_path = $text->{'logPath'};
         my $err = ARUDB::exec_sp(
                                                                                        'aru_cumulative_request.add_series_parameters'
                                                                                        ,$dest_series_id
                                                                                        ,$dest_lbl.'-TASK_STATUS'
                                                                                        ,96183
                                                                                        ,$status,1)if($status);
            $err = ARUDB::exec_sp(
                      'aru_cumulative_request.add_series_parameters'
                      ,$dest_series_id
                      ,'ADE_BRANCH_STATUS'
                      ,96183
                      ,$status,1)if($status);

            $err = ARUDB::exec_sp(
                                                                          'aru_cumulative_request.add_series_parameters'
                                                                                ,$dest_series_id
                                                                                ,$dest_lbl.'-LOG_PATH',96183,$log_path,1)if($status);
      }
        }
 }
 }
}
sub get_series_product{
  my($self,$series,$patch_type,$version) = @_;
   $series =~ s/\s+$patch_type\s{1}$version//gi;
   return $series;
}
sub is_valid_series{
   my($self,$sereis_name) = @_;
  if($sereis_name !~ /\s+((\d+)\.){4}(\d+)$/gi){
     return 0;
  }
   my $sql = "select *
              from   aru_cum_patch_series
              where  lower(series_name) ='".lc($sereis_name)."'";
   my @results = ARUDB::dynamic_query($sql);
   if(scalar(@results) > 0){
        return 1;
   }
        return 0;
}
sub is_ru_dev_series{
   my($self,$series_name) = @_;
   my $sql = "select series_name,product_name,
                     base_release_id
              from   aru_cum_patch_series
              where  series_name = '".$series_name."'";

   my @result = ARUDB::dynamic_query($sql);
      if(scalar(@result) < 1){
           return 0;
      }
      $series_name  = $result[0]->[0];
   my $product_name = $result[0]->[1];
   my $base_rel_id  = $result[0]->[2];
   my $is_it_new_RM = ARUDB::exec_sf_boolean
                              ('aru_cumulative_request.is_new_release_model',
                               $base_rel_id);
   my $temp = $product_name;
   my $num_words = 0;
   ++$num_words while $temp =~ /\S+/g;
      if($is_it_new_RM){
         if($series_name =~ /Release Update 0\.0\.0\.0/gi){
               return 1;
         }elsif($series_name =~ /1\.0\.0\.0/gi){
               return 1;
         }
      }else{
         if($num_words > 1){
              return 1;
         }
         if($product_name =~ /Dev/gi){
               return 1;
         }

      }
   return 0;

}

sub calculat_series_family{
    my($self,$src_family,$src_type,$dest_type) = @_;
    my $patch_types = {'34501'=>'BP','34502'=>'PSU','34503'=>'SPU','35350'=>'SP','96084' => 'RUE'
                        ,'96021' => 'RU','96022' => 'RUR','96023' => 'CEU','96085' => 'RUI'};
    my $src_desc  = $patch_types->{$src_type};
    my $dest_desc = $patch_types->{$dest_type};
    $src_family   =~ s/$src_desc/$dest_desc/gi;
    return $src_family;
}
sub get_series_info{
   my($self,$series_name) = @_;
   my $sql ="select series_id,patch_type,
                    product_id,family_name,
                    base_release_id,product_name
             from   aru_cum_patch_series
             where  lower(series_name) ='".lc($series_name)."'";
   my @results = ARUDB::dynamic_query($sql);
   return @results;
}
sub get_previous_release{
   my ($self,$src_ser_id,$dest_rel_id,$patch) = @_;
   my $sql = "select s.patch_type,r.release_version
              from  aru_cum_patch_releases r,
                    aru_cum_patch_series s
              where r.series_id = s.series_id
              and   r.release_id = $dest_rel_id";
    my @results = ARUDB::dynamic_query($sql);
    my $dest_patch_type = $results[0]->[0];
    my $dest_rel_version = $results[0]->[1];
       if($dest_patch_type == 96022 || $dest_patch_type == 96023){
          my $sql = "select substr(to_char(
                            to_date(last_updated_date,
                            'YYYY-MM-DD HH24:MI:SS'),
                            'YYMMDD.HH24MI'),1,6),release_version
                     from  aru_cum_patch_releases
                     where series_id = $src_ser_id
                     and   status_id in (34523,34524)
                     and   last_updated_date is not null
                     order by aru_backport_util.get_numeric_version
                     (release_version) desc";
             @results = ARUDB::dynamic_query($sql);
              if(scalar(@results)<1){
                  return 1;
              }
             return $results[0]->[0];
       }elsif($dest_patch_type == 96021 || $dest_patch_type == 96085){
          $sql = "select s.product_name,s.product_id,
                        s.base_release_id,p.parameter_value
                  from  aru_cum_patch_series s,
                        aru_cum_patch_series_params p
                  where s.series_id = p.series_id
                  and   s.series_id = $src_ser_id
                  and   p.parameter_name = 'COMPONENT'";
          @results = ARUDB::dynamic_query($sql);
          my $src_prod_name = $results[0]->[0];
          my $aru_prod_id   = $results[0]->[1];
          my $base_rel_id   = $results[0]->[2];
          my $comp          = uc($results[0]->[3]);
          my @series_prods      = split('\s+',$src_prod_name);
          my $ser_starts_with   = $series_prods[0];
          $sql = "select r.release_id
                  from   aru_cum_patch_releases r,
                         aru_cum_patch_series s,
                         aru_cum_patch_series_params p
                  where  r.series_id = s.series_id
                  and    s.series_id = p.series_id
                  and    p.parameter_name = 'COMPONENT'
                  and    upper(p.parameter_value) ='".$comp."'
                  and    s.base_release_id = $base_rel_id
                  and    s.product_id = $aru_prod_id
                  and    s.patch_type in (96021,96022,96023,96085)
                  and    s.product_name like '%".$ser_starts_with."%'
                  and    r.release_name <> s.series_name
                  and    r.status_id in (34523,34524)
                  and    r.release_id not in ($dest_rel_id)
                  order by aru_backport_util.get_numeric_version(r.release_version) desc";
           @results = ARUDB::dynamic_query($sql);
           my $prv_rel_id = $results[0]->[0];
          if($prv_rel_id){
           $sql = "select substr(to_char(
                            to_date(last_updated_date,
                            'YYYY-MM-DD HH24:MI:SS'),
                            'YYMMDD.HH24MI'),1,6),release_version
                     from  aru_cum_patch_releases
                     where release_id = $prv_rel_id
                     and   status_id in (34523,34524)
                     and   last_updated_date is not null
                     order by aru_backport_util.get_numeric_version
                     (release_version) desc";
             @results = ARUDB::dynamic_query($sql);
             return $results[0]->[0];
           }else{
                return 1;
           }

       }else{
           $sql = "select s.product_name,s.product_id,
                        s.base_release_id,p.parameter_value,s.patch_type
                  from  aru_cum_patch_series s,
                        aru_cum_patch_series_params p
                  where s.series_id = p.series_id
                  and   s.series_id = $src_ser_id
                  and   p.parameter_name = 'COMPONENT'";
          @results = ARUDB::dynamic_query($sql);
          my $src_prod_name = $results[0]->[0];
          my $aru_prod_id   = $results[0]->[1];
          my $base_rel_id   = $results[0]->[2];
          my $comp          = uc($results[0]->[3]);
          my $src_patch_type = $results[0]->[4];
          my @series_prods      = split('\s+',$src_prod_name);
          my $ser_starts_with   = $series_prods[0];
           $sql = "select r.release_id
                  from   aru_cum_patch_releases r,
                         aru_cum_patch_series s,
                         aru_cum_patch_series_params p
                  where  r.series_id = s.series_id
                  and    s.series_id = p.series_id
                  and    p.parameter_name = 'COMPONENT'
                  and    upper(p.parameter_value) ='".$comp."'
                  and    s.base_release_id = $base_rel_id
                  and    s.product_id = $aru_prod_id
                  and    s.patch_type in ($src_patch_type,$dest_patch_type)
                  and    s.product_name like '%".$ser_starts_with."%'
                  and    r.release_name <> s.series_name
                  and    r.release_id not in ($dest_rel_id)
                  and    r.status_id in (34523,34524)
                  order by aru_backport_util.get_numeric_version(r.release_version) desc";
           @results = ARUDB::dynamic_query($sql);
           my $prv_rel_id = $results[0]->[0];
              if($prv_rel_id){
                $sql = "select substr(to_char(
                            to_date(last_updated_date,
                            'YYYY-MM-DD HH24:MI:SS'),
                            'YYMMDD.HH24MI'),1,6),release_version
                     from  aru_cum_patch_releases
                     where release_id = $prv_rel_id
                     and   status_id in (34523,34524)
                     and   last_updated_date is not null
                     order by aru_backport_util.get_numeric_version
                     (release_version) desc";
              @results = ARUDB::dynamic_query($sql);
              return $results[0]->[0];
            }else{
                return 1;
           }



       }
         return 1;
}
sub bootstrap_prv_patch{
 my ($self,$src_series_id,$dest_series_id,
              $dest_rel_id,$patch,$user_id) = @_;
 my $abs_req_id = $self->{'abs_req_id'};
=for comment 
my $runUsingScript = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                               'RUN PYTHON NON DELTA CONTENT');
if(lc $runUsingScript == 'on'){
  eval{
    # my $command = "python -u /scratch/rchamant/prod/pls_33266325/isd/pm/ARUForms/remote_machine.py";
    my $command = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                               'RUN PYTHON COMMAND');
    my $remote_param = "config=dev&sub=bootstrap_prv_patch&abs_req_id=$abs_req_id&src_series_id=$src_series_id&dest_series_id=$dest_series_id&dest_rel_id=$dest_rel_id&patch=$patch&user_id=$user_id"; 
    $command = $command." $remote_param";
    my $pid = open3(my $chld_in, my $chld_out, my $chld_err = gensym,$command);
    waitpid( $pid, 0 );
    my $child_exit_status = $? >> 8;
  };
  my $temp_sql = "select count(*) from aru_cum_abs_req_info
                  where abs_request_id = $abs_req_id
                  and module_id = 96456
                  and message like 'Python: Non Delta contnet bootstrap completed'";
  my $temp_res = ARUDB::dynamic_query($temp_sql);
  if ($temp_res->[0] == 1){
    return;
  }
}
=cut    
 add_abs_log_info($abs_req_id,96456,"Started Bootstrapping Non Delta Content...");
 add_abs_log_info($abs_req_id,96456,"Indnetifying the Released date of previous release cyle...");
 my $fifth_part =  $self->get_previous_release($src_series_id,
                                               $dest_rel_id,
                                               $patch);
 add_abs_log_info($abs_req_id,96456,"Indnetified the previous release YYMMDD:$fifth_part") if($fifth_part);
 my $query = "select series_name
              from   aru_cum_patch_series
              where  series_id = $src_series_id";
 my @query_result = ARUDB::dynamic_query($query);
 my $src_ser_name = $query_result[0]->[0];
    $query = "select abbr.related_bug_number as bug
  from   aru_bugfix_bug_relationships abbr,
         isd_bugdb_bugs ibb
  where  abbr.related_bug_number = ibb.bug_number and
         abbr.relation_type in (609,610,613 )and
         abbr.bugfix_id = (select bugfix_id
                           from ARU_BUGFIXES
                           where BUGFIX_RPTNO=$patch
                            and rownum=1)
        and  abbr.related_bug_number not in (
              select base_bug
              from   aru_cum_codeline_requests
              where  series_id = $dest_series_id
         )
       and abbr.related_bug_number in (
              select base_bug
              from   aru_cum_codeline_requests
              where  series_id = $src_series_id
              and    status_id in (34583,96302,34597,34610,34598,34599,96371,34588)
         ) ";
   if($src_ser_name && $src_ser_name =~ /Exa/gi){
        $query = " select base_bug
              from   aru_cum_codeline_requests
              where  series_id = $src_series_id
              and    status_id in (34583,96302,34597,34610,34598,34599,96371,34588)
              and    base_bug not in (
                    select base_bug
                    from   aru_cum_codeline_requests
                    where  series_id = $dest_series_id
                    and    status_id in (34583,96302,34597,34610,34598,34599,96371,34588)
              )";

   }
   @query_result = ARUDB::dynamic_query($query);
 my $nonDeltaCount = scalar(@query_result);
 add_abs_log_info($abs_req_id,96456,"Total Non Delta Content:$nonDeltaCount");
 if($fifth_part && scalar @query_result > 0){
      my  $sql = "select series_name,
                         aru_backport_util.ignore_fifth_segment(
                         aru_cumulative_request.get_series_version(series_name))
                  from aru_cum_patch_series
                  where series_id=$dest_series_id";
      my  @results = ARUDB::dynamic_query($sql);
      my  $series_name = $results[0]->[0];
      my  $rel_version = $results[0]->[1].'.'.$fifth_part;
          $sql = "select release_id,status_id
                  from   aru_cum_patch_releases
                  where  series_id = $dest_series_id
                  and    release_name like '%".$rel_version."'";
          @results = ARUDB::dynamic_query($sql);
      my  $release_id = $results[0]->[0];
      my  $status_id  = $results[0]->[1];
      my @params = ({name => "pv_series_name",
                      data => $series_name},
                     {name => "pv_release_version",
                      data => $rel_version},
                     {name => "pn_user_id",
                      data => $user_id},
                     {name => "pno_release_id",
                      data => \$release_id});

        my $error = ARUDB::exec_sp('aru_cumulative_request.create_release',
                               @params) if(!$release_id);
        if($status_id != 34523 && $status_id !=34524){
          $error  = $self->_update_release_status($release_id,
                                                        34526,
                                                        $user_id);
          $error  = $self->_update_release_status($release_id,
                                                        34522,
                                                        $user_id);
          $error  = $self->_update_release_status($release_id,
                                                        34523,
                                                        $user_id);
          $error  = $self->_update_release_status($release_id,
                                                        34524,
                                                        $user_id);
         }
         my $statusmsg;
        my $i= 0;
         foreach my $request (@query_result)
         {
                 $i= $i+1;
            my @params = ({name => "pn_bug_number",
                       data => $request->[0]},
                      {name => "pn_series_id",
                       data => $dest_series_id},
                      {name => "pn_release_id",
                       data =>  $release_id},
                      {name => "pn_patch",
                       data =>  $patch},
                      {name => "pvo_request_msg" ,
                       data => \$statusmsg});
    eval{
                        my $error =
            ARUDB::exec_sp('aru_cumulative_request.process_bootstrap_content',
                           @params );
        };
           my @request_info = split(/:/,$statusmsg);

          add_abs_log_info($abs_req_id,96456,"$i".')'."Bug#".$request_info[0].' CR#'.$request_info[1].":".$request_info[2]);
         }
         add_abs_log_info($abs_req_id,96456,'Non Delta contnet bootstrap completed');

  }
}
sub get_open_cis{
   my($self,$cgi,$req) = @_;
   my $rel_version = URI::Escape::uri_unescape($cgi->param("release_version"));
   my $series_type = URI::Escape::uri_unescape($cgi->param("series_type"));
   my $response;
   my $error;
   my $ret_json;
   my %op=();
   my $fixed_bugs='{}';
   if($ENV{REQUEST_METHOD} ne 'GET'){
         $error    = 'unsupported http method';
         goto LABEL;
   }
   if(!$rel_version && !$series_type){
        $error    = 'CPM release version/series_type is needed!';
        goto LABEL;
   }
   if($rel_version || $series_type){
      my $sql;
      my @result;
       if($rel_version){
       $sql = "select release_id,series_id
                from   aru_cum_patch_releases
                where  release_version ='".$rel_version."'";
     @result  = ARUDB::dynamic_query($sql);
     my $release_id = $result[0]->[0];

          if(!$release_id){
        $error    = 'Invalid CPM release version!';
        goto LABEL;

     }

     $sql = " select codeline_request_id ,base_bug,
                     backport_bug,
                     aru_cumulative_request.get_blr_txn(backport_bug) as txn,
                     br.status
              from   aru_cum_codeline_requests cr,
                     aru_cum_patch_releases r,
                     bugdb_rpthead_v br
              where cr.release_id = r.release_id
              and   r.release_id = $release_id
              and   cr.status_id = 34581
              and   br.rptno = cr.backport_bug
              and   br.status not in (35,80,74,75,90,93,53)";


      @result  = ARUDB::dynamic_query($sql);
       }elsif($series_type){
            $sql = "select codeline_request_id ,base_bug,
                     backport_bug,
                     aru_cumulative_request.get_blr_txn(backport_bug) as txn,
                     br.status
              from   aru_cum_codeline_requests cr,
                     aru_cum_patch_releases r,
                     bugdb_rpthead_v br,
                     aru_cum_patch_series acps
              where cr.release_id = r.release_id
              and   acps.series_id = r.series_id
              and   acps.series_id = cr.series_id
              and   r.status_id in (34523,34522)
              and   cr.status_id = 34581
              and   br.rptno = cr.backport_bug
              and   br.status not in (35,80,74,75,90,93,53)
              and   aru_cumulative_request.get_series_parameter_value(acps.series_id, 'Series Type') = '$series_type'";
   @result  = ARUDB::dynamic_query($sql);

      }

for(@result){
             my $cr = $_->[0];
             my $base_bug = $_->[1];
             my $ci = $_->[2];
             my $txn = $_->[3];
             my $ci_status = $_->[4];
             next if(!$txn);
             next if($txn eq 'NO_TXN');
            my $txn_status = ARUDB::exec_sf('aru_cumulative_request.get_backport_txn_status',$txn);
            next if(uc($txn_status) ne 'MERGED');
            $op{$cr}{'content_req_id'} = $cr;
            $op{$cr}{'base_bug'} = $base_bug;
            $op{$cr}{'backport_bug'} =$ci;
            $op{$cr}{'transaction'} = $txn;
            $op{$cr}{'ci_status'} = $ci_status;
          }
          if(%op){
              $error    = '';
              $fixed_bugs = encode_json \%op;
              goto LABEL;
          }

}

LABEL:
$ret_json = <<JSON_RET;
         {
           "error": "$error",
           "content":$fixed_bugs

         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;

}
sub add_abs_log_info{
    my($abs_req_id,$module_id,$message) = @_;
   if($abs_req_id && $module_id && $message){
     eval{
    my $log_error = ARUDB::exec_sp('aru_cumulative_request.add_abs_req_info',
                                  $abs_req_id,$module_id,$message);
        };
   }
}

#
# Bug 30651348 - QA Certified Patches
#

sub get_qa_certified_aru{
   my($self,$cgi,$req) = @_;
   my $label = URI::Escape::uri_unescape($cgi->param("label"));
   my $response;
   my $error;
   my $ret_json;
   my %op=();
   my $aru_ids='{}';
   if($ENV{REQUEST_METHOD} ne 'GET'){
         $error    = 'unsupported http method';
         goto LABEL;
   }
   if(!$label){
        $error    = 'Label is required!';
        goto LABEL;
   }
   if($label){
      my $sql = "select  parameter_value
                   from  aru_cum_patch_release_params
                   where parameter_type=34615
                   and   parameter_name like '".$label."%'";

     my @result  = ARUDB::dynamic_query($sql);
     my $aru_id = $result[0]->[0];

     if(!$aru_id){
         $error    = 'Invalid release label!';
        goto LABEL;
     }

     $sql = " select  abr.bugfix_request_id, abr.qa_certified
                from  aru_bugfix_requests abr,
                      aru_bugfix_requests abr1
                where abr.release_id = abr1.release_id
                and   abr.platform_id = abr1.platform_id
                and   abr.bug_number = abr1.bug_number
                and   abr1.bugfix_request_id = $aru_id
                                and   abr.qa_certified is not null";
      @result  = ARUDB::dynamic_query($sql);
for(@result){
             my $aru_no = $_->[0];
            my $qa_certified = $_->[1];
            $op{$aru_no}{'ARU'} = $aru_no;
            $op{$aru_no}{'QA_Certified'} = $qa_certified;
          }
          if(%op){
              $error    = '';
              $aru_ids = encode_json \%op;
              goto LABEL;
          }


   }
LABEL:
$ret_json = <<JSON_RET;
         {
           "error": "$error",
           "content":$aru_ids

         }
JSON_RET

$self->send_cgi_header($req);
print STDOUT $ret_json;

}

sub create_placeholder_ci
{
    my ($self, $bugfixes, $series_name, $series_id, $release_id) = @_;
    my ($cust_name) = "";
    my $ci_bugfixes = "";
    my $ci_bug_tag = "";

    eval
    {
       $cust_name = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                                   'IDM_AUTO_CI_CUSTOMER');
    };
    if ($@)
    {
      $cust_name = "INTERNAL";
    }

    eval
    {
       $ci_bug_tag = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                                    'IDM_CI_BUG_TAG');
    };

    my $user_id    =  '1';

    #my $sql = "select regexp_replace(upper(substr($label_name,  ".
    #           "instr($label_name,'_',-1,1)+1)), '(.*)\.(.*)\.(.*)', '\1.\2')".
    #           " merge_time from dual";

    #my @sql_result = ARUDB::dynamic_query($sql);
    #my $label_merge_time  = $sql_result[0]->[0];

    my $comment = "Semi annual patch autofiling";
    #my $tag_list = "";

    my @bugfix_nums = split(',',$bugfixes);
    $self->{prev_filed_cis} = "";
    foreach my $bugfix_rptno (@bugfix_nums)
    {
        my ($txn_name);

        my $ci_exists_query = " select  distinct brv.rptno   ".
                              " from aru_cum_codeline_requests accr, aru_cum_patch_releases acpr, bugdb_rpthead_v brv ".
                              " where accr.base_bug = $bugfix_rptno ".
                              " and accr.series_id = $series_id ".
                            #  " and accr.release_id = $release_id ".
                              " and acpr.release_id = accr.release_id ".
                              " and brv.base_rptno = accr.base_bug ".
                              " and brv.utility_version = acpr.release_version ".
                              " and brv.generic_or_port_specific = 'Z'";
        my @ci_result  = ARUDB::dynamic_query($ci_exists_query);
        my $ci_bug_num = $ci_result[0]->[0];

        if (defined $ci_bug_num && $ci_bug_num ne "" && $ci_bug_num > 0)
        {
           # CI exists for the same series, so skipping these bugfixes for creating CIs.
           # since this is already included in the previous patch.
           $self->{prev_filed_cis} .= $ci_bug_num .",";
           next;
        }
        my $txn_merge_time = "";
        my @params =  ({name => "pv_blr_bug",
                        data => $bugfix_rptno},
                       {name => "pb_store_transaction",
                        data => 0,
                        type => "boolean"});
       # eval{
       #     $txn_name = ARUDB::exec_sf("aru.aru_ade_util.get_blr_transaction_name",
       #                                 @params);
       #     if (defined $txn_name && $txn_name ne "")
       #     {
       #         $txn_merge_time = ARUDB::exec_sf("aru.aru_ade_util.get_transaction_merge_time",
       #                                           $txn_name);
       #     }
       # };
        my ($current_list, $prev_list, $error_list);

        @params =  ({name => "pv_bug_list ",
                    data => $bugfix_rptno},
                   {name => "pv_series_list",
                    data => $series_id},
                   {name => "pv_customer",
                    data => $cust_name},
                 #  {name => "pv_tag_list",
                 #   data => $tag_list},
                   {name => "pv_request_reason",
                    data => $comment},
                   {name => "pn_user_id",
                    data => $user_id},
                   {name => "pvo_current_list",
                    data => \$current_list},
                   {name => "pvo_previous_list",
                    data => \$prev_list},
                   {name => "pvo_error_list",
                    data => \$error_list});
         my $error = ARUDB::exec_sp('aru.aru_cumulative_request.request_content_api',
                                @params);

         my $request_id = "";
         my ($release_version);
         if (defined $current_list && $current_list ne "")
         {
             $request_id = $current_list;
         }
         elsif (defined $prev_list && $prev_list ne "")
         {
             $request_id = $prev_list;
         }

         if (defined $request_id && $request_id ne "")
         {
             @params   =  ({name => "p_codeline_request_id",
                           data => $request_id},
                           {name => "p_col_name",
                            data => 'release_id' },
                           {name => "p_col_value",
                            data => $release_id});
              ARUDB::exec_sp('aru.aru_cumulative_request.update_cum_codeline_requests',
                             @params);
              my $ci_bug;
              @params =  ({name => "pn_codeline_request_id",
                      data => $request_id},
                     {name => "pno_ci_rptno",
                      data => \$ci_bug },
                     {name => "pb_auto_close_ci",
                      data => 1 ,
                      type => "boolean"},
                     {name => "pb_force_ci",
                      data => 1,
                      type => "boolean" },
                     {name => "pv_comments",
                      data => 'Placeholder CI'});
            $error = ARUDB::exec_sp('aru.aru_cumulative_request.create_ci',
                                    @params);

            if (defined $ci_bug && $ci_bug ne "")
            {
               my $rel_sql = " select brv.utility_version , acpr.release_id ".
                             " from bugdb_rpthead_v brv, aru_cum_patch_releases acpr ".
                             " where brv.rptno = $ci_bug ".
                             " and acpr.release_version = brv.utility_version ";
               my @rel_result  = ARUDB::dynamic_query($rel_sql);
               $release_version = $rel_result[0]->[0];
               #$release_id = $rel_result[0]->[1];
               my $tag_err = ARUDB::exec_sf('bugdb.create_or_append_bug_tag',
                                             $ci_bug, $ci_bug_tag);
               $ci_bugfixes .= $ci_bug.",";
            }

            # If the bugfixes merged prior to the branch cut off time then close the CIs
            # others should be left open
            if (defined $ci_bug && $ci_bug ne "" )
            {
                if (! defined $user_id || $user_id eq "")
                {
                  $user_id = 1;
                }
                $self->close_placeholder_ci($request_id, $ci_bug, $release_id,
                          $release_version, $user_id, $txn_name, $txn_merge_time);
            }

         }
    }
    $ci_bugfixes =~ s/,$//g;
    $self->{prev_filed_cis} =~ s/,$//g;
    return $ci_bugfixes;
}

sub close_placeholder_ci
{
    my ($self, $request_id, $ci_bug, $release_id, $release_version, $user_id, $txn_name, $txn_merge_time) = @_;

    my @params   =  ({name => "pn_codeline_request_id",
                           data => $request_id},
                           {name => "pn_request_status",
                            data => 34563 },
                           {name => "pn_user_id" ,
                            data => $user_id},
                           {name => "pv_comments",
                            data => 'Request updated to Approved status.'});

    my $error = ARUDB::exec_sp('aru.aru_cumulative_request.update_request_status',
                               @params);

    @params =  ({name => "pn_bug_number",
                  data => $ci_bug},
                 {name => "pn_status",
                  data => 35 },
                 {name => "pv_programmer",
                  data => 'ARU' },
                 {name => "pv_version_fixed",
                  data => $release_version } );
    ARUDB::exec_sp("bugdb.update_bug",@params);
    my $ci_text_msg = "Automatically closed as part of semi-annual patch ".
            " content for $release_version ";
    ARUDB::exec_sp("aru_backport_util.add_bug_text", $ci_bug, $ci_text_msg);

    if (defined $txn_name && $txn_name ne "")
    {
         ARUDB::exec_sp("aru.aru_cumulative_request.add_request_attributes",
                         $request_id, 'ADE Transaction Name', $txn_name);
    }
    #ARUDB::exec_sp("aru_cumulative_request.add_request_attributes",
    #                $request_id, 'ADE Merged Branch', $branch_name);
    if (defined $txn_merge_time && $txn_merge_time ne "")
    {
       ARUDB::exec_sp("aru.aru_cumulative_request.add_request_attributes",
                    $request_id,  'ADE Merged Timestamp', $txn_merge_time);
    }

    @params =  ({name => "pn_codeline_request_id",
                  data => $request_id},
                 {name => "pn_request_status",
                  data => 34588 },
                 {name => "pn_release_id",
                  data => $release_id },
                 {name => "pn_user_id",
                  data => $user_id } ,
                 {name => "pv_comments",
                  data => 'Request updated to Approved,Code Merged.'});
    ARUDB::exec_sp("aru.aru_cumulative_request.update_request_status",
                    @params);

}

#
# Bug 31941160 - Mask Bug RestAPI
#

sub mask_cpm_bugs{
   my($self,$cgi,$req) = @_;
   my $version = URI::Escape::uri_unescape($cgi->param("version"));
   my $mask_bugs = URI::Escape::uri_unescape($cgi->param("mask_bugs")).'';
   my $response;
   my @bug_list;
   my @cpm_req_list;
   my $error;
   my $ret_json;
   my %op=();
   my $aru_ids='{}';
   if($ENV{REQUEST_METHOD} ne 'GET'){
         $error    = 'unsupported http method';
         goto LABEL;
   }
   if(!$version){
        $error    = 'Version is required!';
        goto LABEL;
   }
   if($version !~ /\D/)
   {
        $error    = 'Invalid Version Provided!';
        goto LABEL;
   }
   my $count = 0;
   if($version){

     my ($mask_label) = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                                       'MASK_LABEL');

     my $sql = "select accr.base_bug, accr.codeline_request_id from
                       aru_cum_codeline_requests accr,
                       aru_cum_patch_releases acr
                where  acr.release_version = '$version'
                  and  accr.release_id = acr.release_id";

     my ($result)  = ARUDB::dynamic_query_object($sql);
     if(!$result)
     {
         $error    = 'Invalid Version!';
         goto LABEL;
     }
     
     while (($mask_bugs eq 'Y') && (my $row = $result->next_row()))
     {
         my $bug_tags =  ARUDB::exec_sf('aru.bugdb.query_bug_tag',$row->[0]);

         if($bug_tags =~ $mask_label)
         {
             ARUDB::exec_sp('aru_cumulative_request.update_is_masked',
                            $row->[1],
                            'Y');
         }
        #  else
        #  {
        #      ARUDB::exec_sp('aru_cumulative_request.update_is_masked',
        #                     $row->[1]);
        #  }
         $count = $count + 1;
     }
     $sql = $sql." and accr.is_masked = 'Y'";
     $result  = ARUDB::dynamic_query_object($sql);
     while (my $row = $result->next_row())
      {
        $count+=1;
        push(@bug_list,$row->[0]);
        push(@cpm_req_list,$row->[1]);   
      }
   }
  $op{"cpm_req_list"} = join( " ," ,@cpm_req_list);
  $op{"bug_list"} = join( " ," ,@bug_list);
   if($count == 0)
   {
      $error    = 'Invalid Version!';
      goto LABEL;
   }
LABEL:
$ret_json = <<JSON_RET;
         {
           "error": "$error",
           "masked_bugs": "$op{'cpm_req_list'}",
           "masked_cpm_req":"$op{'bug_list'}"
         }
JSON_RET

print STDOUT $cgi->header("Content-Type: text/json");
print STDOUT $ret_json;

}



sub get_cpm_supressed_bugs{
   my($self,$cgi,$req) = @_;
   my $version = URI::Escape::uri_unescape($cgi->param("version"));
   my @sup_bug_list;
   my @sup_cpm_req_list;
   my $error;
   my $ret_json;
   my %op=();
   if($ENV{REQUEST_METHOD} ne 'GET'){
         $error    = 'unsupported http method';
         goto LABEL;
   }
   if(!$version){
        $error    = 'Version is required!';
        goto LABEL;
   }
   if($version !~ /\D/)
   {
        $error    = 'Invalid Version Provided!';
        goto LABEL;
   }
   my $count = 0;
   if($version){
      my $sql = "select accr.base_bug, accr.codeline_request_id from
                        aru_cum_codeline_requests accr,
                        aru_cum_patch_releases acr
                  where  acr.release_version = '$version'
                    and  accr.release_id = acr.release_id
                    and accr.is_supressed = 'Y'";

      my ($result)  = ARUDB::dynamic_query_object($sql);
      if(!$result)
      {
          $error    = 'Invalid Version!';
          goto LABEL;
      }
      while (my $row = $result->next_row())
      {
        $count+=1;
        push(@sup_cpm_req_list,'Base Bug: '.$row->[0].' - RequestId: '.$row->[1]);
        # push(@sup_bug_list,$row->[0]);
    }
   }
   
  
  $op{"sup_cpm_req_list"} = join( " ," ,@sup_cpm_req_list);
  # $op{"sup_bug_lis"}      = join( "-" ,@sup_bug_list);
my $supressed_bugs = encode_json \%op;
LABEL:
$ret_json = <<JSON_RET;
         {
           "error": "$error",
           "count": "$count",
           "supressed_bugs" : $supressed_bugs
           
         }
JSON_RET
#  $self->send_cgi_header($req);
print STDOUT $cgi->header("Content-Type: text/json");
print STDOUT $ret_json;

}

1;

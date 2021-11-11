use strict;
#use warnings;
# Script to verify cross rel gaps
use lib $ENV{ISD_HOME}."/pm";

use ConfigLoader 'ARUForms::Config' => "$ENV{ISD_HOME}/conf/aruforms.pl";
use ARUForms::ARUForm;
# use ARUForms::BackportCLIReview;
# use ARUForms::FastBranchSetup;
use JSON;
use     vars qw(@ISA);
use Data::Dumper;
use Log;
use DateUtils;
# use ARUForms::JIRA;
# use ARUForms::BackportCLIUpdate;
use ARUDB;
# use     APF::PBuild::Util;
my %options;
$options{show_logon}  = 1;
$options{retry_count} = ISD::Config::retry_count;
$options{retry_sleep} = ISD::Config::retry_sleep;
$options{RETRY_DIE}   = ISD::Config::retry_die;

#ARUDB::init(ARUForms::Config::connect, %options);
# my $connect ="aruforms/z2Qg8toA\@aru_internal_apps_adx";
# my $connect ="aruforms/aruforms\@sprintdb";
# ARUDB::init($connect);

my $err;
my @params;

sub _update_release_status_
{
    my($abs_req_id,$release_id, $status,$user_id,$label) = @_;
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

   _add_abs_log_info($abs_req_id,96454,"Updating the Release:$releaseVersion status to ".$releaseStatus{$status});
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
 _add_abs_log_info($abs_req_id,96454,'Error in updating the release status.'.$error)if($error);
   return $error;
} 
sub _get_previous_release{
   my ($src_ser_id,$dest_rel_id,$patch) = @_;
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

sub _bootstrap_prv_patch{
 my ($abs_req_id,$src_series_id,$dest_series_id,
              $dest_rel_id,$patch,$user_id) = @_;

 _add_abs_log_info($abs_req_id,96456,"Started Bootstrapping Non Delta Content...");
 _add_abs_log_info($abs_req_id,96456,"Indnetifying the Released date of previous release cyle...");
 my $fifth_part =  _get_previous_release($src_series_id,
                                               $dest_rel_id,
                                               $patch);
 _add_abs_log_info($abs_req_id,96456,"Indnetified the previous release YYMMDD:$fifth_part") if($fifth_part);
 my $query = "select series_name ,base_release_id
              from   aru_cum_patch_series
              where  series_id = $src_series_id";
 my @query_result = ARUDB::dynamic_query($query);
 my $src_ser_name = $query_result[0]->[0];
 my $base_release_id = $query_result[0]->[1];
    $query = "select abbr.related_bug_number as bug
  from   aru_bugfix_bug_relationships abbr,
         isd_bugdb_bugs ibb
  where  abbr.related_bug_number = ibb.bug_number and
         abbr.relation_type in (609,610,613 )and
         abbr.bugfix_id = (select bugfix_id
                           from ARU_BUGFIXES
                           where BUGFIX_RPTNO=$patch
                           and release_id=$base_release_id
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
 _add_abs_log_info($abs_req_id,96456,"Python: Total Non Delta Content:$nonDeltaCount");
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
          $error  = _update_release_status_($abs_req_id,$release_id,
                                                        34526,
                                                        $user_id);
          $error  = _update_release_status_($abs_req_id,$release_id,
                                                        34522,
                                                        $user_id);
          $error  = _update_release_status_($abs_req_id,$release_id,
                                                        34523,
                                                        $user_id);
          $error  = _update_release_status_($abs_req_id,$release_id,
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

          _add_abs_log_info($abs_req_id,96456,"$i".')'."Bug#".$request_info[0].' CR#'.$request_info[1].":".$request_info[2]);
         }
         _add_abs_log_info($abs_req_id,96456,'Non Delta contnet bootstrap completed');

  }
}



sub _bootstrap_content{
 my ($abs_req_id_,$src_series_id,$patch,$series_id,$release_id,$label_date,$user_id) = @_;
 my $statusmsg;
  my $abs_req_id = $abs_req_id_;
    $label_date =~ s/\.//gi;
    if(length($label_date) == 6){
       $label_date = $label_date.'0000';
    }
   if(!$user_id){
        $user_id = 1;
   }

  _add_abs_log_info($abs_req_id,96455,"Fetching Detla contnet...");
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
                                              from ARU_BUGFIXES ab
                                              inner join aru_releases ar on  ar.release_id=ab.release_id
                                              inner join aru_cum_patch_series acps on ar.release_id=acps.base_release_id
                                              where BUGFIX_RPTNO=$patch
                                              and acps.series_id = $series_id
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
                                              from ARU_BUGFIXES ab
                                              inner join aru_releases ar on  ar.release_id=ab.release_id
                                              inner join aru_cum_patch_series acps on ar.release_id=acps.base_release_id
                                              where BUGFIX_RPTNO=$patch
                                              and acps.series_id = $series_id
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
 _add_abs_log_info($abs_req_id,96455,"Python: Total Delta Content:$totalDelta");
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
       _add_abs_log_info($abs_req_id,96455,"$i)Creating Content Request for the Bug#$base_bug");

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
                    _change_ci_abstract($backport,$release_id) if($backport);
                    _copy_cr_attr($request_id,$cr);
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
    _add_abs_log_info($abs_req_id,96455,"Content Request#$cr created for the Bug $base_bug") if(!$err);
    print "Content Request#$cr created for the Bug $base_bug \n";
   _add_abs_log_info($abs_req_id,96455,"Errorn in creating CR for  the Bug $base_bug,$err") if($err);
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

 _add_abs_log_info($abs_req_id,96455,"Dev RU content request #$request_id status changed to Branched.") if(!$err);
    _add_abs_log_info($abs_req_id,96455,"Error in moving DEV RU Content Bug $base_bug status to Branched.") if($err);


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
                 _update_base_bug($cr);


                _change_ci_abstract($backport,$release_id) if($backport);
                   _copy_cr_attr($request_id,$cr);
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
    _add_abs_log_info($abs_req_id,96455,"Delta Content Bootstrap completed.")


 }
eval{
   _process_open_cis($abs_req_id,$src_series_id,$patch);
};

}

sub _process_open_cis{
    my($abs_req_id_,$source_series_id,$patch) = @_;
    my $abs_req_id = $abs_req_id_;
    _add_abs_log_info($abs_req_id,96458,"Updating the Next Release cycle contnet...");
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
                                              from ARU_BUGFIXES ab
                                              inner join aru_releases ar on  ar.release_id=ab.release_id
                                              inner join aru_cum_patch_series acps on ar.release_id=acps.base_release_id
                                              where BUGFIX_RPTNO=$patch
                                              and acps.series_id = $source_series_id
                                              and rownum=1)

                )
            ";
      my @res =  ARUDB::dynamic_query($sql);
      my $nextRelcycleCount = scalar @res;
       _add_abs_log_info($abs_req_id,96458,"Total Next Release Cycle content:$nextRelcycleCount");
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

          _add_abs_log_info($abs_req_id,96458,"CI Bug#$ci_bug is prefixed with Next Release cycle");
             _change_ci_abstract($ci_bug,$rel_id,$request_id,$series_id);
          }
      }




}



sub _change_ci_abstract{
 my ($ci_bug,$release_id,$request_id,$series_id) = @_;
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
               #   if($rel_cycle){
                     #  $subject = $rel_cycle.' '.$subject;
                     $subject = "Jan2022".' '.$subject;

               #   }

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
sub _copy_cr_attr{
  my($src_cr,$dest_cr) = @_;
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
sub _update_base_bug{

my ($cr) = @_;
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





sub _add_abs_log_info{
    my($abs_req_id,$module_id,$message) = @_;
   if($abs_req_id && $module_id && $message){
     eval{
    my $log_error = ARUDB::exec_sp('aru_cumulative_request.add_abs_req_info',
                                  $abs_req_id,$module_id,$message);
        };
   }
}

eval{

print "---Started----\n";
# my $connect ="aruforms/aruforms\@sprintdb";
# my $connect ="aruforms/z2Qg8toA\@aru_internal_apps_adx";
ARUDB::init($connect);

print "----Bootstrap function called----\n";
my ($abs_req_id,$src_series_id,$patch,$dest_series_id,$release_id,$label_date,$user_id);
# _bootstrap_content(2802,19751,33220272,21993,606887,211019,1);

 my $sql = "select sysdate from dual";
 my @res =  ARUDB::dynamic_query($sql);
 my $status = $res[0]->[0];
print "series _name $status \n ";
print "----Bootstrap function completed----\n";


#   my $remote_param = "sub=bootstrap_prv_patch&abs_req_id=$abs_req_id&src_series_id=$src_series_id&dest_series_id=$dest_series_id&dest_rel_id=$dest_rel_id&patch=$patch&user_id=$user_id"; 
my $param = @_;
my @spl = split('&', $param);
my @input_params;
# displaying result using foreach loop
foreach my $i (@spl) 
{
    my @value = split('=', $i);
    print "Value $value[0] $value[1] \n";
      if($i!~ /^(config|sub)/ ){
      push(@input_params, $value[1]);
      }
    
}
if($spl[1] =~/bootstrap_prv_patch/g){
   # _bootstrap_prv_patch(@input_params);
   print("calling non delta content\n");
}
#   my $remote_param = "sub=bootstrap_content&abs_req_id=$abs_req_id&src_series_id=$src_series_id&patch=$patch&series_id=$series_id&release_id=$release_id&label_date=$label_date&user_id=$user_id"; 
elsif($spl[1] =~/bootstrap_content/g){
   # _bootstrap_content(@input_params);
      print("calling delta content\n");
}

#  my ($abs_req_id,$src_series_id,$dest_series_id,
#               $dest_rel_id,$patch,$user_id)
print("calling non delta content\n");
# _bootstrap_prv_patch(3043,19751,22433,608791,33495189,8824276);

#  _bootstrap_prv_patch(3044,19791,22434,608792,33525204,8824276);
# _bootstrap_prv_patch(3003,19731,22373,608710,33500773,8824276);
_bootstrap_prv_patch(2984,21813,22374,608712,33192793,8824276);
 print("done non delta content\n");

};
# return;
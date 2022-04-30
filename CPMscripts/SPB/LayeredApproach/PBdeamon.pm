#
# Copyright (c) 2015 by Oracle Corporation. All Rights Reserved.
#
#
package APF::PBuild::PBDaemon;

use     File::Basename;
use     ISD::Daemon::Processor::Request;
use     ISD::Const;
use     ISD::LDAP;
use     ISD::Mail;
use     ARUDB;
use     DoRemoteCmd;
use     APF::Init;
use     APF::PBuild::ErrorHandle;
use     APF::PBuild::PreProcess;
use     APF::PBuild::GenericBuild;
use     APF::PBuild::TemplateGen;
use     APF::PBuild::PortBuild;
use     APF::PBuild::Merge;
use     APF::PBuild::PostProcess;
use     APF::PBuild::InstallTest;
use     APF::PBuild::PluginBuild;
use     APF::PBuild::Util;
use     APF::PBuild::Query;
use     APF::PBuild::FarmJob;
use     APF::PBuild::Farm;
use     APF::PBuild::BundlePatch;
use 	APF::PBuild::MetadataBundlePatch;
use     APF::PBuild::GIPSUBundlePatch;
use     APF::PBuild::CDBundlePatch;
use     APF::PBuild::PCW;
use     APF::PBuild::FMW12c;
use     APF::PBuild::StackPatchBundle;
use     APF::PBuild::AutoPort;
use     APF::PBuild::DescribeTrans;
use     APF::PBuild::RebaseTxns;
use     APF::PBuild::CreateNewBranchInfo;
use     APF::PBuild::cpct_common;
use     APF::PBuild::ValidateRequest;
use     APF::PBuild::APFCorrectiveActions;
use     APF::PBuild::SystemPatch;
use     APF::PBuild::MetadataSystemPatch;
use     APF::PBuild::BI::Util;
use     APF::PBuild::BI::DiffTool;
use     APF::PBuild::QAInstallTest;
use     APF::PBuild::FABuildAnalysis;
use     APF::PBuild::ADEAPFTriggers;
use     APF::PBuild::CloudRequest;
use     ARU::BugfixRequest;
use     XML::LibXML;
use     ARU::Const;
use     Data::Dumper;
use     ISD::Const;
use     DoSystemCmd;
use     Debug;
use     vars qw(@ISA);
use     strict;
use     Date::Calc qw(Today_and_Now);
use     APF::PBuild::RetryRequest;
use     APF::PBuild::OrchestrateAPF;
use     APF::PBuild::GoldImage;
use     APF::PBuild::BuildOneoff;
use     APF::PBuild::KspareUpdates;
use     APF::PBuild::BackportUtils;
use     APF::PBuild::FMW11g;


use   ConfigLoader "APF::Config" => "$ENV{ISD_HOME}/conf/pbuild.pl";
use   ConfigLoader "ERR::Config" =>
                 "$ENV{ISD_HOME}/conf/apf_installtest_err_codes.pl";
use ConfigLoader "PV::Config" => "$ENV{ISD_HOME}/pm/APF/PBuild/".
    "utils/proactivevalidations/conf/validations.pl";
use constant TMPL_EXT => '.tmpl';

my $initialized = 0;
@ISA = qw(ISD::Daemon::Processor::Request);
sub new
{
    my ($class, $request_id) = @_;

    my $base_work = APF::Config::apf_base_work;
    my $view      = APF::Config::viewstore;

    my $self = bless (ISD::Daemon::Processor::Request->new(
                                  request_id => $request_id,
                                  work_dir   => "$base_work/$request_id"),
                      $class);

    $self->{request_id} = $request_id;
    $self->{base_work}  = $base_work;
    $self->{config_file} = "$ENV{ISD_HOME}/conf/pbuild.pl";

    _init() unless ($initialized == 1);

    $ENV{REQUEST_WORK_AREA} = "$base_work/$request_id";
    $ENV{REQUEST_ID} = $request_id;

    return $self;
}

#
# To add APF, ARU and ISD related Queries to ARUDB
#
sub _init
{
    APF::Init::add_queries();
    $initialized = 1;

    #
    # Verify and set ade okinit ticket if required.
    #
    set_ade_okinit_info();

    eval {
      my $retry_count = eval "APF::Config::retry_count";
      $retry_count ||= 10;
      my $retry_die = eval "APF::Config::retry_die";
      $retry_die ||= 5;

      ARUDB::set_parameter("RETRY_COUNT", $retry_count);
      ARUDB::set_parameter("RETRY_DIE",   $retry_die);
    };
}

# This method will be executed by the Daemon
#
sub execute
{
    my ($self) = @_;

    my $req_param   = $self->{params}->{st_apf_build};

    $self->_can_request_run();

    if ($req_param =~ /corrective_action/) {
      $self->run_on_retry_step("corrective_action", ISD::Const::st_apf_preproc);
    } else {
      $self->run_on_retry_step("run_preprocess", ISD::Const::st_apf_preproc);
    }
}

#
#Updates the src ctrl type for base release GIT backports
#

sub initialize_git_src_ctrl_type
{
    my ($self, $bug) = @_;
    my $src_ctrl_type;
    my ($base_bug, $utility_ver, $platform_id, $prod_id, $category,
    $sub_component) =  $self->{preprocess}->get_bug_details_from_bugdb($bug);

    ($src_ctrl_type) = ARUDB::single_row_query("GET_SRC_CTRL_TYPE_FOR_RELEASE",
                                                $utility_ver);
    $self->{log_fh}->print("Source control type of this release $utility_ver is $src_ctrl_type\n");
    $self->{src_ctrl_type} = $src_ctrl_type;
    $self->{log_fh}->print("Before OIM check: $self->{src_ctrl_type}\n");
    if ($self->{src_ctrl_type} eq "" || !defined($self->{src_ctrl_type}))
    {
        #For base release GIT backports, source control type cannot be fetched from CPM
        
        $self->{log_fh}->print("Checking if ir is an OIM base release backport \n");

        $self->{preprocess}->is_oim_backport_bug($bug);

        if (defined $self->{preprocess}->{aru_obj}->{oim_backport_bug} &&
                $self->{preprocess}->{aru_obj}->{oim_backport_bug} == 1)
        {
            $self->{log_fh}->print("This is OIM backport : $self->{preprocess}->{aru_obj}->{oim_backport_bug}\n");

            if ($self->{preprocess}->{aru_obj}->{comp_ver} =~ /(\d+).(\d+).(\d+).(\d+).0/)
            {
                $self->{log_fh}->print("This is a OIM GIT backport on base release: $self->{preprocess}->{aru_obj}->{comp_ver}\n");
                $self->{src_ctrl_type} = "git";
            }

        }
    }
}


#
# Preprocessing
#
sub run_preprocess
{
   
    my ($self) = @_;

    my $req_param   = $self->{params}->{st_apf_build};
    


    my %params;
    foreach my $i (split('!',$req_param))
    {
        my ($key, $value) = split(':',$i);
        $params{$key} = $value;
        if ((defined($value)) && $value =~ /^http/) {
            $params{lc($key)} = $value;
        }
        else {
            $params{lc($key)} = lc($value);
        }
        $self->{aru_log}->print("Request Parameters : $key - $value \n");
    }

    if ($self->{request_id}) {
      $0 .= " - request_id=$self->{request_id},action=$params{action}" .
            ",bug=$params{bug},aru=$params{aru_no}";
    }

    #
    # Store the ISD request id number
    #
    $params{request_id} = $self->{request_id};
    $params{log_fh}     = $self->{aru_log};

    $self->{params}     = \%params;
    $self->{params}->{grid_id}     = $self->{request}->{grid_id};

    die ("Action is not specified for this request")
        unless($params{action});

    my $success;
    my $log_fh = $self->{log_fh} = $self->{params}->{log_fh} = $self->{aru_log};
    #
    # Check for APF support for given request
    #
    my $request_status;

    #
    # validation checks are not needed for proactive validations
    # and Gold image creation
    #
    if ($params{action} =~ /proactive_validations|submit_pv_requests|create_goldimage|build_oneoff/i)
    {
        $self->{valid_request} = 1;
        $request_status = 1;
    }


    eval {
        $self->{preprocess} = APF::PBuild::PreProcess->new(\%params)
                                         unless $self->{preprocess};

        $self->{preprocess}->add_log_parameter();
    };


    eval {

        $request_status = $self->validate_request($self->{params})
                          if (! defined( $self->{valid_request}));
    };

    unless ($@)
    {
        if ( !defined($self->{request_status}) && (! $request_status) )
        {
            my $err_msg;
            $err_msg = $self->{err_msg} if $self->{err_msg} ne '';
            $log_fh->print("\n$err_msg\n");

            $self->{valid_request} = 0;
            $self->{err_msg} = $err_msg;
        }
        else
        {
            $self->{valid_request} = 1;
            $log_fh->print("\n*Request Passed*\n");
        }

        #
        # Execute the respective action
        # 1.$success is set to 1,when no error
        # is caught in the eval statement
        # 2.$success is set to undef,when
        # any error is caught in the eval statement
        #
        $success = eval("\$self->_$params{action}(\\\%params); return 1")
                                                if $self->{valid_request};
        $success = 0 if $@;
    }

    #
    # $@ is not storing the die message for some special cases.
    # Hence adding a new check flag $success to handle the error properly.
    # Ref Bug:9293573
    #
    if ((!$success) || ($@))
    {
        my $action  = $params{action_desc} || $params{action} || "";
        my $err_msg = $action . ": " .  $@;

        if (ref($@) eq "HASH") {
          $err_msg = $action . ": " .  $@->{error_message}
                                           if ($@->{error_message});
          $self->{failed_task_obj} = $@->{task_obj} if ($@->{task_obj});
        }

        #
        # Throwing following error msg when $@ is empty
        #
        $err_msg = "Error in $action, see log for more details"
            unless ($@);
        if ($err_msg =~ /This needs to be reviewed by developer/ && 
            $err_msg =~ /Farm regressions are being reported for this backport/) {
            $self->{preprocess}->{farm_dev_assignment_diff_found} = 1;
        }
        if (defined $self->{force_retry} && $self->{force_retry}
           && $err_msg=~/error from bug/i)
        {
             $err_msg = $action . ": APF will retry after ".
                        PB::Config::farm_wait_time . " secs";
        }

        #
        # Workaround for bug-24747997
        # The force_retry will be set only when PBDaemon is using FarmJob module
        # and not Farm module which is used only for backports right now
        #
        if ($action eq "Check Results" && not defined($self->{force_retry}))
        {
            $err_msg = "Check Results: Farm regressions were reported for " .
                       "this backport. Handing over the transaction"
                           unless ($@);
        }

        if ($params{auto_template})
        {
            my $aru_obj;
            my $testname = $self->_get_test_name($aru_obj, $err_msg);
            $self->retry_request();
            die($err_msg);
        }

        die($err_msg) if ($params{describe} ||
                          $params{create_new_branch} ||
                          $params{seed_series_info} ||
                          $params{rebase} ||
                          $params{track_hudson_build});

        $err_msg = $self->{err_msg} if ( defined($self->{err_msg}) &&
                                                             (! $@) );

        $self->{preprocess} = APF::PBuild::PreProcess->new(\%params)
                                         unless $self->{preprocess};

        $self->{die} = 1;
        $self->{err_msg} ||= $err_msg;

        if (! $params{bug} && $params{aru_no})
        {
            my ($patch_request) =
                ARUDB::single_row_query("GET_PSE_BUG_NO", $params{aru_no});

            if (!$patch_request)
            {
                $params{bug} = $self->{bug};
                $params{auto_port} = 1;
            }

        }

        if ($action !~ /build_oneoff/) {
          $self->{log_fh}->print("\n\n [DEBUG:PBDaemon.pm] farm_dev_assignment_diff_found set as $self->{preprocess}->{farm_dev_assignment_diff_found} \n");
          $self->_handle_failure($self->{bugfix_request_id},
                                 $self->{preprocess}, $err_msg,
                                 $params{bug},
                                 $params{auto_port})
                                     if ($err_msg !~ /APF will retry/);
        }

        #
        # Handle Error Patterns
        #
        $err_msg = $self->_handle_err_msg($err_msg);

        die($err_msg) if ($self->{die} == 1);
    }
}


sub _handle_err_msg
{
    my ($self, $err_msg) = @_;
    my $gen_or_port = '';
    my $patch_type = '';

    my $log_fh = $self->{aru_log};

    if(defined($self->{_err_handle}))
    {
        if( $self->{_err_handle}->{cd_ci_txn} ne '' ||
            $self->{_err_handle}->{cd_qa_status} ne '')
        {
            $patch_type = 'cd';
        }

        if($patch_type eq '' &&
           defined($self->{_err_handle}->{label}) &&
           $self->{_err_handle}->{label} ne '')
       {
           $patch_type = 'bundle';
       }

    }

    if ($patch_type eq '' &&
        defined($self->{patch_type}) &&
        ($self->{patch_type} eq ARU::Const::ptype_cumulative_build))
    {
        $patch_type = 'cumulative';
    }

    $log_fh->print("\nPatch Type:$patch_type:\n");

     if ($patch_type ne '')
     {

         if($self->{gen_port} eq '')
         {
             my $pse = $self->{params}->{bug};
             if($pse ne '')
             {
                 my ($rptno, $base_rptno, $comp_ver, $status, $version,
                     $port_id, $genport, $product_id, $category,
                     $sub_component, $customer, $version_fixed,
                     $test_name, $rptd_by)
                     = ARUDB::single_row_query("GET_BUG_DETAILS",
                     $pse);
                 $gen_or_port = $genport;
             }
         }else{
                $gen_or_port = $self->{gen_port};
         }

         $log_fh->print("\nGen or Port :$gen_or_port:\n");

         if($gen_or_port ne '' && $patch_type ne '')
         {
             my $new_err_msg =
                 $self->_get_err_patterns($gen_or_port,
                                          $patch_type,
                                          $err_msg);
             $log_fh->print("\nNew Err Msg:$new_err_msg:\n");
             return $new_err_msg;
         }
     }
     return $err_msg;
}


sub _get_err_patterns
{
    my ($self, $gen_or_port, $patch_type, $err_msg) = @_;

    my $orig_err_msg = $err_msg;

    my $log_fh = $self->{aru_log};

    my @query_res = ARUDB::query('GET_ERROR_PATTERNS',
                                 $gen_or_port,
                                 $patch_type);

    foreach my $rec ( @query_res )
    {
        my($err_template, $err_desc) = @$rec;

        my $regex = eval { qr/^(.*?)$err_template/ };
        next if $@;

        my $pre_part = '';
        if($err_msg =~ /^(.*?)$err_template/)
        {
           $pre_part = $1;
        }
        if($err_msg =~ /${pre_part}$err_template/)
        {
            my $regex_str = "\$err_msg =~ ".
                "s/${pre_part}$err_template/${pre_part}$err_desc/";

            eval( $regex_str);

            next if $@;

            last;
        }
    }
    return $err_msg if $err_msg =~ /\w+/;
    return $orig_err_msg;
}


#
# bug 24514534: retry of request should not be happen for
#     closed PSE and PSE which are in developer's queue.
#
sub suspend_retry_request
{
    my ($self, $params, $preprocess) = @_;
    my $log_fh = $self->{aru_log};
    my $bug = $params->{bug};
    my ($param_value) = ARUDB::single_row_query("GET_ARU_PARAM",
                                  'ENABLE_RETRY_SUSPEND_LOGIC');
    return unless($param_value);

    $preprocess  = APF::PBuild::PreProcess->new($params)
            if(!defined $preprocess);
    my $gen_or_port = $preprocess->get_gen_port($bug);

    #
    # For PSE(s) Check if the bug status is open or not before proceeding
    # Disable this check for FMW12c PSEs
    #
    eval {
     my ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component, $abstract, $transaction_name);

    ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component) =
            $preprocess->get_bug_details_from_bugdb($bug);

    my ($platform_id) = ARUDB::single_row_query("GET_APF_PLATFORM_ID",
                                                $bugdb_platform_id);
    $preprocess->{platform_id} = $platform_id;

    my $bundle_label;
    my ($product_id, $product_abbr) =
        APF::PBuild::Util::get_aru_product_id($bugdb_prod_id, $utility_ver,
                                              $bundle_label, $log_fh);
     $preprocess->{version} = $utility_ver;
     $preprocess->{product_id} = $product_id;

     my @release_details =
        $preprocess->get_release_details($bug, $base_bug, $product_id, 1);

    my $cpct_release_id;
    my $is_cpct_release = ARUDB::exec_sf_boolean('aru.pbuild.is_cpct_release',
                                                 $bug,'',
                                                 \$cpct_release_id);

    if ($is_cpct_release)
    {
        @release_details = ARUDB::query('GET_RELEASE_INFO_CPCT',
                                        $cpct_release_id);
    }

    my ($release_name, $release_id, $rls_long_name);

    foreach my $current_release (@release_details)
    {
        ($release_name, $release_id, $rls_long_name) = @$current_release;
        #
        # for BPs & Psu releases, the pad_version of utility version returns
        # the same value
        #
        my ($bug_version) = ARUDB::single_row_query('GET_BUG_VERSION',$bug );

        last if ($bug_version =~/BUNDLE/) &&
            ($rls_long_name =~/BP/);
    }
    $preprocess->{release_id} = $release_id;
    };

    eval {
             if ( $self->{request_id} && ($gen_or_port eq 'O') &&
                  ! $preprocess->is_fmw12c() )
             {
                 my $l_user_id = ARU::Const::apf_userid;
                 my ($l_status, $l_programmer)
                     = ARUDB::single_row_query("GET_STATUS_ASSIGNEE", $bug);

                 my $is_aru_in_valid_status = 1;
                 my $comment = "";
                 $comment = "$bug is in status $l_status which is not valid to process" 
                                 if (($l_status == 90) || ($l_status == 93));
                 $comment = "$bug is assigned to $l_programmer and not PBUILD" 
                                 if ($l_status == 11 && $l_programmer ne "PBUILD");
   
                 # Get request type code 
                 my ($isd_req_type_code) = 
                          ARUDB::single_row_query("GET_REQUEST_TYPE_CODE",
                                                  $self->{request_id});
                 if ($isd_req_type_code == ISD::Const::st_apf_install_type) {
                   my $aru_no = $params->{aru_no} || "";
                   if ($aru_no) {
                     my $aru_obj = ARU::BugfixRequest->new($aru_no);
                     $aru_obj->get_details();
                     my @aru_skip_status_codes = 
                            (ARU::Const::patch_ftped_dev_qa,
                             ARU::Const::patch_ftped_support,
                             ARU::Const::patch_deleted);
                     if (exists $aru_obj->{status_id} &&
                         (grep/$aru_obj->{status_id}/, @aru_skip_status_codes)) {
                       $is_aru_in_valid_status = 0;
                       $comment = "ARU $params->{aru_no} is in status " .
                                  "$aru_obj->{status} which is not valid " .
                                  "to process";
                     }
                   }
                 }

                 if (($l_status == 90) || ($l_status == 93) || 
                     ($is_aru_in_valid_status == 0) ||
                     ($l_status == 11 && $l_programmer ne "PBUILD")) {

                     $log_fh->print("$comment, aborting the current request\n") if ($log_fh);
                     $preprocess->free_throttle_resource($self->{request_id},
                                        ISD::Const::isd_request_stat_succ);
                     ARUDB::exec_sp('isd_request.abort_request',
                                     $self->{request_id},
                                     $l_user_id,
                                    "$comment - $bug status $l_status,$l_programmer");
                    exit APF::Const::exit_code_term;
                 }
            }
    };
}

#
# This method is responsible for patch build
# a. Get the transaction information from BUGDB and ADE
# b. Store the information in ARU
# c. Compile the Files
# d. Package the patch
# e. Push the patch to repository.
#
sub _request
{
    my ($self, $params) = @_;

    my $log_fh = $self->{aru_log};
    my $bug    = $params->{bug};
    my $bundle_label = $params->{label};
    my $bundle_type  = $params->{type};
    my $sql_patch_only = $params->{sql_patch_only};
    my $cd_ci_txn    = $params->{cd_ci_txn} || "";
    my $cd_qa_status = $params->{cd_qa_status} || "";
    my $preprocess      = APF::PBuild::PreProcess->new($params);
    $self->{preprocess} = $preprocess;

    $self->{_err_handle} = $params;

    $params->{user_id} = $self->{params}->{user_id};

    #
    # If its a describe request
    #
    if ($params->{describe})
    {
        $params->{log_fh}          = $self->{aru_log};

        my $describetrans          = APF::PBuild::DescribeTrans->new($params);
        $self->{describetrans}     = $describetrans;
        $describetrans->{user_id}  = $self->{params}->{user_id};
        $params->{action_desc} = "Request DescribeTrans Info";
        $log_fh->print_header("Request DescribeTrans Info\n");
        $describetrans->get_transaction_info($preprocess);
        if (! defined $describetrans->{multiple_txns} ||
            $describetrans->{multiple_txns} != 1)
        {
            $params->{action_desc} = "Generate DescribeTrans Info";
            $log_fh->print_header("Generate DescribeTrans Info \n");
        }
        $describetrans->build($preprocess);
        return;
    }

    if ($params->{rebase})
    {
        $params->{log_fh}          = $self->{aru_log};
        my $rebase_txns          = APF::PBuild::RebaseTxns->new($params);
        $self->{rebase_txns}     = $rebase_txns;
        $rebase_txns->{user_id}  = $self->{params}->{user_id};
        $params->{action_desc} = "Process Rebase Request";
        $log_fh->print_header("Process Rebase Request\n");
        $rebase_txns->process_rebase($preprocess);
        return;
    }

    #
    # If its a request to seed the new branch information into ARU
    #
    if ($params->{create_new_branch})
    {
        $params->{log_fh}          = $self->{aru_log};

        my $new_branch_info        =
            APF::PBuild::CreateNewBranchInfo->new($params);
        $self->{create_new_branch}    = $new_branch_info;
        $new_branch_info->{user_id} = $self->{params}->{user_id};

        $params->{action_desc} = "Validate New Branch Info";
        $log_fh->print_header("Validate New Branch Info \n");
        $new_branch_info->validate_branch_info($preprocess);

        $params->{action_desc} = "Create Release Info";
        $log_fh->print_header("Create Release Info \n");
        $new_branch_info->create_release_info($preprocess);

        $params->{action_desc} = "Create Product Release Info";
        $log_fh->print_header("Create Product Release Info \n");
        $new_branch_info->create_product_release_info($preprocess);

        $params->{action_desc} = "Create Branch Info";
        $log_fh->print_header("Create Branch Info \n");
        $new_branch_info->create_branch_info($preprocess);
        return;
    }

    if ($params->{seed_series_info})
    {
        $params->{log_fh}          = $self->{aru_log};

        my $seed_series_info        =
            APF::PBuild::CreateNewBranchInfo->new($params);
        $self->{seed_series_info}    = $seed_series_info;
        $seed_series_info->{user_id} = $self->{params}->{user_id};

        $params->{action_desc} = "Validate Series Info";
        $log_fh->print_header("Validate Series Info \n");
        $seed_series_info->validate_series_info($preprocess);

        $params->{action_desc} = "Update Series Info";
        $log_fh->print_header("Update Series Info \n");
        $seed_series_info->create_branch_info($preprocess);

        return;
    }

    my $gen_or_port = $preprocess->get_gen_port($bug);

    #
    # For PSE(s) Check if the bug status is open or not before proceeding
    # for a Closed PSE/in developr's control no need to proceed further
    #

    $self->suspend_retry_request($params, $preprocess); # checks and suspends

    #
    # Send notification for valid backport requests
    #
    $self->send_notification_for_backports($bug,$gen_or_port);


    #
    # Check if its a autoport request
    #
    my $auto_port = $params->{auto_port};

    my $type = ($gen_or_port eq "M") ? "MLR" :
               ($gen_or_port eq "B") ? "BLR" :
               ($gen_or_port eq "Z") ? "CI" :
               ($gen_or_port eq "I") ? "RFI" : "PSE";

    if (($gen_or_port eq "M") || ($gen_or_port eq "B") ||
        ($gen_or_port eq "I") || ($gen_or_port eq "Z"))
    {
        $self->{gen_port} = $gen_or_port;
    }

    $params->{action_desc} = "Request $type";

    if (! defined APF::Config::enable_throttling_pse ||
        APF::Config::enable_throttling_pse != 1)
    {
        ARUDB::exec_sp("aru.apf_request_status.update_throttle_requests");
    }


    #
    # Check if RFI processing is enabled or not
    #
    my $enable_rfi = APF::Config::enable_rfi;
    die("APF does not support request for RFIs")
        if ($gen_or_port eq "I" && $enable_rfi == 0);

    # bug 8340452 - provide data for unsupported releases
    #
    my ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component, $abstract, $transaction_name);

    ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component) =
            $preprocess->get_bug_details_from_bugdb($bug);

    my ($platform_id) = ARUDB::single_row_query("GET_APF_PLATFORM_ID",
                                                $bugdb_platform_id);
    die("Unable to find platform_id for BUGDB platform id $bugdb_platform_id")
        unless($platform_id);

    $self->{platform_id} = $platform_id;

    $self->{category} = $category;

    my ($product_id, $product_abbr) =
        APF::PBuild::Util::get_aru_product_id($bugdb_prod_id, $utility_ver,
                                              $bundle_label, $log_fh);

    die("APF does not support requests for this BUGDB product: " .
        "$bugdb_prod_id")
        unless($product_id);

    #
    # To avoid the manually filed BLRs processing for RDBMS product by APF
    #
    if ($gen_or_port eq "B")
    {
        my $product_type = ARU::Const::product_type_family;
        my ($parent_product_id) = ARUDB::single_row_query(
                                               "GET_PARENT_PROD_ID",
                                               $product_id,
                                               $product_type);

        if (! defined $parent_product_id || $parent_product_id eq "")
        {
            $parent_product_id = $product_id;
        }

        if ($parent_product_id == ARU::Const::product_oracle_database)
        {
            my ($rptd_by) = ARUDB::single_row_query("GET_REPORTED_BY",
                                                    $bug);

            if ($rptd_by ne 'ARU')
            {
                my $is_manual_supp_backport = ARUDB::exec_sf
                    ('aru.pbuild.is_manual_exadata_backport',
                     $bug);

                if ($is_manual_supp_backport == 0)
                {
                   my $manual_blr_txt =
                          "Please file patch requests (BLRs) using the ARU ".
                          "Backport utility (or using the interface in DWB ".
                          "as appropriate).\n\n" .
                          "The plan to close and request re-filing of ".
                          "manually filed BLRs was approved by Sustaining".
                          " Engineering. If there are questions or " .
                          "concerns, please have the issue raised by filing".
                          " a bug against 1057/APF.";

                   my ($def_assignee, $ostatus) =
                                   ARUDB::single_row_query(
                                           'GET_DEFAULT_ASSIGNEE',
                                            $bug);
                   $self->_update_bug($bug,
                               {status     => 53,
                                programmer => $def_assignee,
                                test_name  => 'APF-UNSUPPORTED-PROCESS'});
                   $manual_blr_txt =
                         "This manually filed BLR request " .
                         "is being closed automatically.\n" . $manual_blr_txt;

                   ARUDB::exec_sp ('bugdb.async_create_bug_text',
                                   $bug,$manual_blr_txt);

                   die("APF does not support Manually filed backports".
                       " except for the 11.2.0.2.* EXADATA and ".
                       " version between 11.2.0.3.1EXADBBP and ".
                       "11.2.0.3.4EXADBBP Releases");
               }
            }
        }
    }

    #
    # To avoid the retried requests getting processed
    # and abort them gracefully
    #
    my $destroytrans_action = 0;
    $destroytrans_action = 1 
        if (exists($params->{destroytrans}) && defined($params->{destroytrans}) && $params->{destroytrans} ne "");

    if (($gen_or_port eq "B" || $gen_or_port eq "Z") 
        && $destroytrans_action == 0) {
        my $product_type = ARU::Const::product_type_family;
        my ($parent_product_id) = ARUDB::single_row_query(
                                               "GET_PARENT_PROD_ID",
                                               $product_id,
                                               $product_type);
        if (! defined $parent_product_id || $parent_product_id eq "")
        {     
            $parent_product_id = $product_id;
        }     

        if ($parent_product_id == ARU::Const::product_oracle_database)
        {
           my ($is_refresh_req) = ARUDB::single_row_query('IS_REFRESH_TXN_REQUEST',$bug);
           if ($is_refresh_req >= 1)
           {
               $log_fh->print("DEBUG_RETRY: backport : $bug is refresh txn request, hence txn status check not needed ,processing further\n");
           }
           else
           {
               $log_fh->print("DEBUG_RETRY: backport : $bug is not refresh txn request, hence txn status check needed and stop processing further\n");
               my ($trans_name) = ARUDB::single_row_query("GET_BACKPORT_TRANSACTION_NAME",
                                             $bug);
               $log_fh->print("DEBUG_RETRY: Transaction $trans_name\n");

	       #
	       # Handle cases when transaction does not exist
	       #                      
	      
               my $txn_info = {};
	       if ($trans_name) {
                   eval{($txn_info) = $preprocess->get_transaction_files_using_rest_api($trans_name);};
                   if (!(exists($txn_info->{ERROR}) && $txn_info->{ERROR} == 1))
                   {
	               my @txn_files = @{$txn_info->{files}};
                       my $txn_state = $txn_info->{STATE};
                       my $txn_files_count =  scalar(@txn_files);
                       $log_fh->print("DEBUG_RETRY:Transaction $trans_name is in state: $txn_state and has the fille : \n" . 
                                      "and txn file count : $txn_files_count\n" .Dumper($txn_info) . "\n");
		
		       if ((defined $txn_state && $txn_state ne "" && $txn_state eq 'CLOSED') &&
                           (defined $txn_files_count && $txn_files_count > 0))
		       {
                           my ($def_assignee) =
                                   ARUDB::single_row_query(
                                           'GET_BACKPORT_TRANSACTION_PREV_ASSIGN',
                                            $bug);
                           if ( !(defined($def_assignee)) || $def_assignee eq "")
                           {
                                 $log_fh->print("Retrieving the def_assignee details directly from the bugdb\n");
                                 my ($def_assignee, $version_fixed, $test_name, $bug_current_status)
                                      = ARUDB::single_row_query("GET_BUG_UPDATE_DETAILS",$bug);
                           }
                           $log_fh->print("DEBUG_RETRY: def_assignee : $def_assignee\n");
                           my $text =
                               "The transaction $trans_name is already in closed state $def_assignee ".
                               "and contains the backend branched elements. ".
                               "Hence closing the backport.";

                           $self->_update_bug($bug,
                                             {status     => 35,
                                              programmer => $def_assignee,
                                              test_name  => 'APF-RETRIED'});
                    
                           die("The transaction $trans_name is already in closed state by $def_assignee ".
                               "and contains the backend branched elements. ".
                               "Hence closing the backport");
                       }
                    }
                }
            }
       }
    
    }
    my @release_details =
        $preprocess->get_release_details($bug, $base_bug, $product_id, 1);

    my $cpct_release_id;
    my $is_cpct_release = ARUDB::exec_sf_boolean('aru.pbuild.is_cpct_release',
                                                 $bug,'',
                                                 \$cpct_release_id);

    if ($is_cpct_release)
    {
        @release_details = ARUDB::query('GET_RELEASE_INFO_CPCT',
                                        $cpct_release_id);
    }

    my ($release_name, $release_id, $rls_long_name);

    foreach my $current_release (@release_details)
    {
        ($release_name, $release_id, $rls_long_name) = @$current_release;
        #
        # for BPs & Psu releases, the pad_version of utility version returns
        # the same value
        #
        my ($bug_version) = ARUDB::single_row_query('GET_BUG_VERSION',$bug );

        last if ($bug_version =~/BUNDLE/) &&
            ($rls_long_name =~/BP/);
    }

    #
    # Disabing FA One-Off
    #
    my $allow_fa_one_off = APF::Config::allow_fa_one_off;
    if($release_id =~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/ &&
                (!$allow_fa_one_off) )
    {
      my $base_g_p = $preprocess->get_gen_port($base_bug)
                                      if($base_bug != $bug);

      if( ($gen_or_port eq 'O' or $base_g_p eq 'O') and
          (!($params->{TXN_NAME} and
          $preprocess->is_nls_bugfix_patch({'txn_name' => $params->{TXN_NAME},
                                            'pse'      => $bug,
                                            'base_bug' => $base_bug}) ) ) )
      {
        if($gen_or_port eq 'O')
        {
         die("ERROR: G/P value of Bug $bug is set to O .".
             "APF does not support FusionApps one-off requests\n")
        }
        elsif($base_g_p eq 'O')
        {
            die("ERROR: G/P value of Base bug $base_bug is set to O. ".
                "APF does not support FusionApps one-off requests\n")
        }
      }

    }



    #
    # Need transaction name to process Fusion patch build requests
    #
    if($release_id =~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/ &&
       ! $bundle_type)
    {
        my $txn_name = $params->{TXN_NAME};
        die("ERROR: Transaction name is required to process Fusion patch " .
            "build requests.\n") if($txn_name eq '');
        $preprocess->{transaction_name} = $txn_name;

        #
        # Need to validate bug type for backport transactions
        # (Only in case of backports, base bug number is
        # different from backport bug number)
        #
        if (defined $txn_name && $base_bug != $bug)
        {
            die("ERROR: Unsupported bug type ($gen_or_port) for " .
                "backport bug $bug. " .
                "APF supports only BLR (B), RFI (I) and CI (Z) " .
                "backports for Fusion.\n")
            if($gen_or_port ne 'B' && $gen_or_port ne 'I' &&
               $gen_or_port ne 'Z');
        }
    }
    
    #
    #check for IDM stackpatch bundle
    #
    if ($bundle_type =~ /stackpatch/i)
    {
        $params->{log_fh}          = $self->{aru_log};
        my $fmw12c                 = APF::PBuild::FMW12c->new($params);
        $preprocess->{release_id} = $fmw12c->{release_id}  = $release_id;
        $fmw12c->{product_id}  = $product_id;
        $fmw12c->{platform_id} = $bugdb_platform_id;
        $fmw12c->{base_bug}    = $base_bug;
        $fmw12c->{bpr_platform}= $params->{platform_id};
        $fmw12c->{version}     = $utility_ver;
        $params->{action_desc} = "Request PSE  $bug";
        $log_fh->print_header("Request PSE: $params->{bug} \n");
        $fmw12c->request_checkin($preprocess);
        return;

    }
    #
    # check for GIPSU bundles
    #
    my ($gipsu_subpatch) = ARUDB::exec_sf(
    'aru_parameter.get_parameter_value', 'GIPSU_SUBPATCH_LABELS');

    if ($bundle_type =~ /dated/i)
    {
        $self->{params_label} = $params->{label};
        $preprocess->{params_label} = $params->{label};
    }
    elsif ($bundle_type =~ /gipsu/i)
    {
        $params->{log_fh}          = $self->{aru_log};
        my $bundlepatch            =
            APF::PBuild::GIPSUBundlePatch->new($params);
        $bundlepatch->{bpr}        = $params->{bug};
        $bundlepatch->{package}    = $params->{package};
        $bundlepatch->{granularity} = $params->{granularity};
        $bundlepatch->{bp_payload}  = $params->{payload};

        $bundlepatch->{bpr_txn}     = $params->{txn}
            if (defined($params->{txn}));

        $bundlepatch->{bpr_third_party} = $params->{third_party}
            if (defined($params->{third_party}));

        $self->{bundlepatch}       = $bundlepatch;
        $self->{bundlepatch}->{bpr} = $params->{bug};

        $preprocess->{release_id}  = $release_id;
        $preprocess->{product_id}  = $product_id;
        $preprocess->{platform_id} = $bugdb_platform_id;
        $preprocess->{base_bug}    = $base_bug;
        $preprocess->{bpr_platform}= $params->{platform_id};
        $params->{action_desc} = "Request GIPSU Subpatch $bug";
        $log_fh->print_header("Request GIPSU Subpatch: $params->{bug} \n");
        $bundlepatch->request_gipsu_checkin($preprocess);
        return;
    }
    elsif ($cd_qa_status)
    {
        $params->{log_fh}          = $self->{aru_log};
        my $bundlepatch            = APF::PBuild::CDBundlePatch->new($params);
        $bundlepatch->{bpr}        = $params->{bug};
        $bundlepatch->{cd_qa_status} = $params->{cd_qa_status};
        $preprocess->{release_id}  = $release_id;
        $preprocess->{product_id}  = $product_id;
        $preprocess->{platform_id} = $bugdb_platform_id;
        $preprocess->{base_bug}    = $base_bug;
        $preprocess->{bpr_platform}= $params->{platform_id};
        $params->{action_desc} = "QA Test Status";
        $params->{cd_qa_status}   =~ tr/a-z/A-Z/;
        $self->{bundlepatch}        = $bundlepatch;
        $self->{bundlepatch}->{bpr} = $params->{bug};
        #
        # QA request
        #
        ARUDB::exec_sp("aru.apf_cd_patch_detail.insert_cd_patch_status",
                       $params->{bug},
                       'CD_REQUEST_ID',$params->{request_id});
        $log_fh->print_header("QA Test Status ($params->{cd_qa_status})");
        $bundlepatch->verify_qa_status($preprocess, $cd_qa_status);
        return;

    }
    elsif ($bundle_label)
    {
        $params->{log_fh}           = $self->{aru_log};
        $log_fh->print("From label: $params->{from_label} , To label: $params->{label}\n");
        if (! defined $sql_patch_only || $sql_patch_only eq "")
        {
         if ((exists($params->{from_label})) &&
            (defined($params->{from_label})) &&
            ($params->{from_label} ne "")) {
            my $dep_label_str;
            eval {
                ($dep_label_str) = ARUDB::exec_sf(
                   'aru_parameter.get_parameter_value', 'BUNDLE_PATCH_DEPENDENT_LABELS');
            };
            if ($@) {
                $log_fh->print("Could not fetch any bundle patch dependent label information\n");
            }
            if((defined($dep_label_str)) && $dep_label_str ne "") {

                my %dependent_hash = split /,|=>/,$dep_label_str;
                my ($act_label) = $params->{from_label} =~ /^(.*?)_/;
                my ($dep_label) = $params->{label} =~ /^(.*?)_/;
                $act_label = uc($act_label);
                my $label_dep_det_key = $act_label . "_" . $self->{platform_id};

                if ((exists($dependent_hash{$label_dep_det_key})) &&
                    (defined($dependent_hash{$label_dep_det_key})) &&
                    ($dependent_hash{$label_dep_det_key} ne "")) {

                    $log_fh->print("The $act_label label should be used for creating view and building ".
                                   "the patch for $dep_label. Hence we will be using the $params->{from_label} to build.");
                    $params->{label} = $params->{from_label};
                    $params->{from_label} = '';
                    $params->{internal_patch_trigger} = 1;
                }
            }
        }
    }
        my $bundlepatch;
        if($params->{meta_data_only} or $params->{label}=~/META_DATA/i){
            $log_fh->print("Instantiating MetadataBundlePatch\n");
            $bundlepatch = APF::PBuild::MetadataBundlePatch->new($params);
        }
        else{
            $log_fh->print("Instantiating BundlePatch\n");
            $bundlepatch = APF::PBuild::BundlePatch->new($params);
        }
        $bundlepatch->{bpr}         = $params->{bug};
        $bundlepatch->{sql_patch_only} = $sql_patch_only;
        $bundlepatch->{package}     = $params->{package};
        $bundlepatch->{granularity} = $params->{granularity};
        $bundlepatch->{bp_payload}  = $params->{payload};
        $bundlepatch->{retry_count} = $params->{req_retry_count};
        $bundlepatch->{force}       = $params->{force}
            if ($params->{force});
        $bundlepatch->{cd_ci_txn}   = $params->{cd_ci_txn}
            if ($params->{cd_ci_txn});
        #
        # CD force failure
        #
        $bundlepatch->{cd_req_status}   = $params->{cd_req_status}
            if ($params->{cd_req_status});
        $bundlepatch->{cd_ci_txn}   = $params->{cd_ci_txn}
            if ($params->{cd_ci_txn});
        #
        # CD force failure
        #
        $bundlepatch->{cd_req_status}   = $params->{cd_req_status}
            if ($params->{cd_req_status});

        $bundlepatch->{bpr_txn}     = $params->{txn}
            if (defined($params->{txn}));

        $bundlepatch->{bpr_third_party} = $params->{third_party}
            if (defined($params->{third_party}));

        $self->{bundlepatch}        = $bundlepatch;
        $self->{bundlepatch}->{bpr} = $params->{bug};

        $preprocess->{release_id}    = $release_id;
        $preprocess->{product_id}    = $product_id;
        $preprocess->{platform_id}   = $bugdb_platform_id;
        $preprocess->{bugdb_prod_id} = $bugdb_prod_id;
        $preprocess->{base_bug}      = $base_bug;
        $preprocess->{bpr_platform}  = $params->{platform_id};
        $preprocess->{sql_patch_only} = $sql_patch_only;

        if ($params->{cd_ci_txn})
        {
            $params->{action_desc} = "BP for $params->{cd_ci_txn}";
            $log_fh->print_header("BP for $params->{cd_ci_txn} \n");
            #
            # pre checkin request
            #
            ARUDB::exec_sp("aru.apf_cd_patch_detail.insert_cd_patch_status",
                           $params->{bug},
                           'CD_REQUEST_ID',$params->{request_id});

        }
        else
        {
            $params->{action_desc} = "Request BPR  $bug";
            $log_fh->print_header("Request BPR: $params->{bug} \n")
                unless($self->skip_header($params));
        }

        $bundlepatch->request_checkin($preprocess);

        $log_fh->print("Debug : $bundlepatch->{bpr_label}, $bugdb_platform_id,  $bundlepatch->{meta_data_only}, $bundlepatch->{sql_patch_only}\n");
		if($bundlepatch->can_trigger_metadata_only_bundle($base_bug, $platform_id)){
			my $metadata_bundlepatch = APF::PBuild::MetadataBundlePatch->new($params);
			$metadata_bundlepatch->trigger_metadata_only_bundle($base_bug);
		}

        return;
    }


    $preprocess->{release_id}  = $release_id;
    $preprocess->{product_id}  = $product_id;
    $preprocess->{platform_id} = $bugdb_platform_id;
    $preprocess->{version}     = $utility_ver;
    $preprocess->is_fmw12c();

    #
    # process fmw12c requests
    #
    if ($preprocess->{is_fmw12c} &&
        (!($gen_or_port eq "Z" || $gen_or_port eq "B" ||
           $gen_or_port eq "I" || $gen_or_port eq "M")))
    {
        $params->{log_fh}          = $self->{aru_log};

        my $orch_ref = APF::PBuild::OrchestrateAPF->new($params);
        $orch_ref->{utility_version} = $utility_ver;
        $orch_ref->post_fmw12c_data($params->{bug},
                                    "create_pse", $params->{request_id});

        my $fmw12c                 = APF::PBuild::FMW12c->new($params);
        $preprocess->{release_id} = $fmw12c->{release_id}  = $release_id;
        $fmw12c->{product_id}  = $product_id;
        $fmw12c->{platform_id} = $bugdb_platform_id;
        $fmw12c->{base_bug}    = $base_bug;
        $fmw12c->{bpr_platform}= $params->{platform_id};
        $fmw12c->{version}     = $utility_ver;
        $params->{action_desc} = "Request PSE  $bug";
        $log_fh->print_header("Request PSE: $params->{bug} \n");
        $fmw12c->request_checkin($preprocess);
        return;
    }

    #
    # If its an auto port patch request
    #
  if ($auto_port)
  {
        $params->{action_desc} = "Request PSE";
        $log_fh->print_header("Request $type\n");

        my $checkin_output = $preprocess->request_auto_port_checkin();

        $log_fh->print_header("Commit Checkin". $checkin_output)
            if $checkin_output;
  }
  else
  {
    if(($gen_or_port eq "O") || ($gen_or_port eq "G") || ($gen_or_port eq "P"))
    {
        if ($release_id =~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
        {
            $self->{blr_bug} = $base_bug;
            if ((($gen_or_port eq "G") || ($gen_or_port eq "P")) &&
                ! $bundle_type)
            {
                 $preprocess->{release_id}  = $release_id;
                 $preprocess->{platform_id} = $platform_id;
                 $self->_test_snowball_dep_chkins($params,$preprocess);
            }
        }
        else
        {
            my $raise_exception = "y";

            #
            # Hack!!
            # For Overlay Exadata BP patches Base bug need to get from Blrs
            #

            my $blr_gen_or_port = $preprocess->get_gen_port($base_bug);

            if( $blr_gen_or_port eq 'B' )
            {
                my ($blr_base_bug, $blr_utility_ver, $blr_bugdb_platform_id,
                    $blr_bugdb_prod_id, $blr_category, $blr_sub_component) =
                    $preprocess->get_bug_details_from_bugdb($base_bug);

                $self->{blr_bug} = ARUDB::exec_sf('aru.bugdb.get_blr_bug',
                                    $blr_base_bug, $blr_utility_ver,
                                    ['boolean',$raise_exception], $product_id);
            }
            else
            {

                my $ignore_blr_status = "y";
                my $blr_no;

                if ($blr_gen_or_port !~ /M/)
                {
                    $self->{blr_bug} =
                        ARUDB::exec_sf('aru.bugdb.get_blr_bug',
                                       $base_bug, $utility_ver,
                                       ['boolean',$raise_exception],
                                       $product_id,
                                       ['boolean',$ignore_blr_status]);
                }

                my ($bugdb_prodid) =
                    ARUDB::single_row_query("GET_BUGDB_PRODUCT_ID",
                                            $preprocess->{product_id} );

                if ($blr_gen_or_port eq 'M')
                {
                    $blr_no = $base_bug;
                }
                else
                {
                    $blr_no = $self->{blr_bug};
                }

                my $is_parallel_pse = 0;
                $preprocess->is_parallel_proc_enabled();
                if ($preprocess->{enabled} == 1)
                {
                    my ($p_blr_sev) =
                        ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                                $blr_no);

                    if (!($preprocess->{only_p1} == 1 &&
                           $p_blr_sev > 1))
                    {
                        $is_parallel_pse = 1;
                    }
                }

                if ((!($preprocess->is_p1_pse_exp_enabled($blr_no))) &&
                    ($is_parallel_pse != 1))
                {
                    $self->{blr_bug} =
                        ARUDB::exec_sf('aru.bugdb.get_blr_bug',
                                       $base_bug, $utility_ver,
                                       ['boolean',$raise_exception],
                                       $product_id);
                }

            }
        }
    }

    if ($gen_or_port eq "O" &&
        $release_id !~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        $preprocess->{product_id} = $product_id;
        $preprocess->{release_id} = $release_id;
        $preprocess->is_parallel_proc_enabled();

        if ($preprocess->{enabled} == 1)
        {
            $log_fh->print("DEBUG: Parallel processing is enabled \n");
            my ($p_severity) =
                ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                        $bug);
            $log_fh->print("DEBUG: BLR BUG: $self->{blr_bug}, $p_severity \n");
            if (! ($preprocess->{only_p1} == 1 && $p_severity > 1))
            {
                my ($blr_status, $blr_prod_id, $blr_priority) =
                    ARUDB::single_row_query("GET_BUG_DETAILS_FROM_BUGDB",
                                            $self->{blr_bug});
                $log_fh->print("DEBUG: BLR Status: $blr_status \n");
                if ($blr_status == 11)
                {
                    my ($bug_tags) = ARUDB::exec_sf('aru.bugdb.query_bug_tag',$bug);
                    my $pse_test_name = APF::Config::parallel_pse_testname;
                    $log_fh->print("DEBUG: TAG: $bug_tags \n");

                    if ($bug_tags !~ /$pse_test_name/)
                    {
                       $log_fh->print("DEBUG: Updating the bug $bug tag \n");
                       eval {
                            my $bug_tag_msg =
                                ARUDB::exec_sf('bugdb.create_or_append_bug_tag',
                                               $bug,
                                               $pse_test_name);
                        };
                    }
                }
            }
        }
    }

    #
    # Handle the case of Fusion Backports
    #
    if ((($gen_or_port eq "B") || ($gen_or_port eq "I") ||
        ($gen_or_port eq "Z")) &&
        $release_id =~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        $type = ($gen_or_port eq "B") ? "BLR" :
                ($gen_or_port eq "I") ? "RFI" :
                ($gen_or_port eq "Z") ? "CI"  : "PSE";
        $self->{blr_bug} = $bug;
        $preprocess->{release_id}  = $release_id;
        $preprocess->{platform_id} = $platform_id;
        $self->_test_snowball_dep_chkins($params,$preprocess);
    }

    my $req_enabled;

    #
    # Check if this platform enabled for porting or not. If the
    # platform is generic, it will be enabled as long as release
    # and product is found.
    #
    if ($self->{platform_id} eq ARU::Const::platform_generic)
    {
        ($req_enabled) = ARUDB::single_row_query("REQUEST_ENABLED_GENERIC",
                                                 $release_id,
                                                 $product_id);
    }
    else
    {
        ($req_enabled) = ARUDB::single_row_query("REQUEST_ENABLED",
                                                 $platform_id,
                                                 $release_id,
                                                 $product_id);
    }

    if (!$release_id || ($release_id && $req_enabled eq '') )
    {
        my $hdr = ($gen_or_port eq "I") ? "Request RFI: $params->{bug}\n" :
                  ($gen_or_port eq "Z") ? "Request CI: $params->{bug}\n" :
                  "Gather Manual Build Info\n";

        $log_fh->print_header($hdr);
    }
    else
    {
        $log_fh->print_header("Request $type: $params->{bug} \n");
    }

    if ($bundle_type =~ /dated/)
    {
        $self->{params_label} = $params->{label};
        $preprocess->{params_label} = $params->{label};
    }

    my ($auto_port,$aru) = (0,0);

    my $auto_obj = APF::PBuild::AutoPort->new({
                                               request_id =>
                                               $self->{request_id},
                                               log_fh => $log_fh,
                                              });

    ($auto_port, $aru)   = $auto_obj->auto_port_validation($bug)
        if ($type eq "PSE" &&
            $release_id !~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/);

    my $request_id =  $self->{request_id};

    $log_fh->print ("Auto Port: $auto_port and ARU :$aru \n");

    #
    # If AutoPorted Patch is available
    #

    if ($auto_port == 1)
    {
        my  $it = new APF::PBuild::InstallTest({bugfix_req_id => $aru,
                                                request_id    =>
                                                $self->{request_id},
                                                log_fh        =>
                                                $preprocess->{log_fh},
                                                pse           => $bug,
                                                params        => $params});

        my $product_id = $it->{aru_obj}->{product_id};
        my $release_id = $it->{aru_obj}->{release};
        my $release = $it->{aru_obj}->{release};
        my $version = APF::PBuild::Util::get_version($release);

        my ($bug_portid, $bug_gen_or_port, $bug_prod_id, $bug_category)
            = ARUDB::single_row_query("GET_BUG_INFO",
                                      $it->{aru_obj}->{bug});
        #
        # check if it is a clusterware patch
        #
        $it->{isPCW} = $it->is_clusterware_patch($bug_category,
                                                 $version,
                                                 $bug_prod_id);

        $it->{source_dir} = $it->get_patch();
        my $output = $it->_unzip_patch_file
            ("$it->{source_dir}/$it->{patch_file}");

        $it->check_sql_filetype($output);
        $it->check_for_kspare_objects($output);
        $it->check_genstub_files($output);

        $it->check_mk_filetype($output);
        $self->{emcc_tag} = $self->_get_emcc_tag($it);

        my $msg = "Automated install tests submitted and completed ".
            "[request id = $request_id].\n";

        my $link = "http://" . APF::Config::url_host_port .
            "/ARU/ViewPatchRequest/process_form?aru=$aru";

        #
        # Check to see if ADE transaction property
        # BACKPORT_PATCH_NOTES is populated. Set $self->{patch_notes}
        # to value in BACKPORT_PATCH_NOTES; block release of the
        # patch for verification.
        #

        $self->{patch_notes} =
            $preprocess->{transaction_details}->{BACKPORT_PATCH_NOTES} || "";

        $it->{sql_auto_release} = 1
           if (($it->{sql_files} == 1) && ($it->{isPCW} == 1));
        # Intentionally leaving these additional debug statements to help
        # the verification process during testing. Can be removed after few months
        $log_fh->print("CHECK IF MANUALLY UPLOADED OR NOT 1 - $params->{aru_no} \n");

        my ($manually_uploaded) = ARUDB::single_row_query('GET_MANUAL_UPLOAD_DETAILS',$params->{aru_no}, ARU::Const::upload_requested);

       $self->{is_a_cloud_patch} = 0;

       # Get the cloud property set on the transaction
       my ($cloud_prop_set) = ARUDB::exec_sf('aru_ade_api.get_txn_property',
                                       $params->{TXN_NAME},
                                       APF::Const::cloud_patch_property, ['boolean', 0]);


       $self->{is_a_cloud_patch} = 1 if ($cloud_prop_set =~ /ver_update,\s*cloud_on/i);
       $log_fh->print("Cloud patch prop value $self->{is_a_cloud_patch} \n");

       $log_fh->print("MK files value before PCW and manual upload check $it->{mk_files} \n");
        $log_fh->print("Manually uploaded value: $manually_uploaded \n");
        $log_fh->print("PCW value: $it->{isPCW} \n");
        $it->{mk_files} = 0 if ($it->{isPCW} == 1 || (defined ($manually_uploaded) && $manually_uploaded == 1) || $self->{is_a_cloud_patch} == 1);
        $log_fh->print("MK files value after PCW and manual upload check $it->{mk_files} \n");

        $it->{spc_sql_files} = 0 if ($it->{isPCW} == 1 || (defined ($manually_uploaded) && $manually_uploaded == 1));
        my ($readme_review_products);

        eval {
            ($readme_review_products) = ARUDB::single_row_query("GET_COMPAT_PARAM",
                                                      "README_REVIEW_PRODUCTS");
        };

        #$log_fh->print("DEBUG_BLANK_README:  REVIEW_PRODUCTS: $readme_review_products\n");
        #$log_fh->print("DEBUG_BLANK_README:  PRODUCT_ID: $it->{aru_obj}->{product_id}\n");

        if ((defined ($readme_review_products)) && $readme_review_products ne "") {
            if ($it->{aru_obj}->{product_id} !~ /^$readme_review_products$/) {
                $it->{blank_readme_html} = 0;
                $it->{blank_readme_txt}  = 0;
                $log_fh->print("DEBUG_BLANK_README:  NOT MATCHED\n");
            }
        }

        $it->{mk_files} = 0 if ($it->{isPCW} == 1);
        $it->{isPCWStop} = 0;
        #$it->{blank_readme_html} = 0 if ($it->{isPCW} != 1);
        if ($it->{isPCW} == 1 && $version =~ /^(12\.|18\.)/) {
            $it->{isPCWStop} = 1;
        }
        $it->{isPCWStop} = 0 if ((defined ($manually_uploaded)) && $manually_uploaded == 1);

        # Disabling the clusterware patch review for all patches
        $it->{isPCWStop} = 0;
        if ((($it->{sql_files}    == 1) &&
             ($it->{sql_auto_release} == 0))
            || ($it->is_security_one_off($base_bug) eq 'Y' &&
               !$it->is_rdbms($it->{aru_obj}->{bug}))
            || $it->{genstubs} == 1
            || $it->{mk_files} == 1
            || $it->{isPCWStop} == 1
            || $it->{blank_readme_html} == 1
            || $it->{blank_readme_txt} == 1
            || $it->{spc_sql_files} == 1)
        {
            $msg = "This is a security one off, " .
                "verify manually and release the patch.\n"
                    if ($it->is_security_one_off($base_bug) eq 'Y' &&
                        !$it->is_rdbms($it->{aru_obj}->{bug}));

            $msg = $it->{sql_auto_release_msg} . "\n"
                      if (($it->{sql_files}    == 1) &&
                           ($it->{sql_auto_release} == 0));

            $msg = $it->{spc_sql_files_msg} . "\n"
                      if ($it->{spc_sql_files} == 1);

            my ($bug_txt,$test_name) = $it->install_test_bug_upg
                ($link,$msg,$version,$base_bug);

            #
            # Update the bugdb.
            #
            $self->_update_bug($bug, {status        => 52,
                                      programmer    => 'PATCHQ',
                                      test_name     => $test_name,
                                      body          => $bug_txt });
        }
        elsif ($product_id == ARU::Const::product_smp_pf ||
               $product_id == ARU::Const::product_emgrid ||
               $product_id == ARU::Const::product_iagent ||
               $product_id == APF::Const::product_id_emdb ||
               $product_id == APF::Const::product_id_emas ||
               $product_id == APF::Const::product_id_emfa ||
               $product_id == APF::Const::product_id_emmos )
        {
            #
            # For em12c check the farm status and set
            # the test_name of pse bug appropriately
            #
            if ($utility_ver !~ /12\.1\.0/)
            {
            my $bug_txt = 'APF built the patch and tested successfully. ' .
                'Verify this patch manually and release the patch';

            #
            # In first phase, do not release the patch
            #
            $self->_update_bug($bug, {status        => 52,
                                      programmer    => 'PATCHQ',
                                      test_name     => 'APF-EM-SUCCESS',
                                      body          => $bug_txt });
            }

        }
        elsif ($it->is_dte_enabled($it->{aru_obj},$product_id))
        {
            my $aru_obj = $it->{aru_obj};

            my $options = {
                           aru_obj       => $aru_obj,
                           product_id    => $aru_obj->{product_id},
                           bugfix_req_id => $aru,
                           pse           => $bug,
                           request_id    => $self->{request_id},
                           log_fh        => $log_fh
                          };

            my $dte = APF::PBuild::DTEInstallTest->new($options);

            $dte->is_fmw11g();

            unless ($dte->{user_id})
            {
                $dte->{user_id} = ARUDB::exec_sf("aru.aru_user.find_user_id",
                                                 $aru_obj->{requested_by});
            }

            $dte->_release($it->{aru_obj},$dte->{user_id},$bug);
        }
        #
        # Update the bugdb.  Note that all finished bugs go to PATCHQ.
        #
        elsif ((!$it->{sql_files}) ||
               (($it->{sql_files}    == 1) &&
                ($it->{sql_auto_release} == 1)))
        {
            $self->{additional_tags} = "APF-SQL-AUTO-RELEASED"
              if (($it->{sql_files} == 1) && ($it->{sql_auto_release} == 1));
                $self->release($aru,$bug,$version);
        }
        else {
            $self->check_install_test_farm_status($bug,$it,$aru,$version);
        }

        $log_fh->print_header("Commit Checkin");

    }
    elsif ($auto_port == 0)
    {
        #
        # Handling the case of Fusion backport bugs
        #
        my $checkin_output;
        if ((($gen_or_port eq "B") || ($gen_or_port eq "I") ||
            ($gen_or_port eq "Z")) &&
            $release_id =~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
        {
            $checkin_output = $preprocess->request_pse_checkin();
        }
        else
        {
            $checkin_output = (($gen_or_port eq "O") || ($gen_or_port eq "G")
                              || ($gen_or_port eq "P")) ?
                              $preprocess->request_pse_checkin() :
                              $preprocess->request_mlr_checkin();
        }
        $log_fh->print_header("Commit Checkin". $checkin_output)
            if $checkin_output;
    }

    #
    # Auto port is in progress.Link the pse req to the auto port request
    #
    elsif ($auto_port == 2)
    {
        $log_fh->print_header("Commit Checkin");
    }
    #
    # If Install Test didnt happen due to the unavailability of DTE or
    # EMS templates for the product
    #
    elsif ($auto_port == 3)
    {
        my  $it = new APF::PBuild::InstallTest({bugfix_req_id => $aru,
                                                request_id    =>
                                                $self->{request_id},
                                                log_fh        =>
                                                $preprocess->{log_fh},
                                                pse           => $bug,
                                                params        => $params});

        my $release = $it->{aru_obj}->{release};
        my $version = APF::PBuild::Util::get_version($release);
        #
        # Update the bug with the relevant information.
        #
        $self->install_test_updates($log_fh, $aru, $version, $bug);
        $log_fh->print_header("Commit Checkin");
    }
  }
}

#
# Process BEA Plugin
#
sub _process_beaplugin
{
    my ($self, $params) = @_;

    my $log_fh = $self->{aru_log};

    my $preprocess       = $self->{preprocess};

    my $bugfix_request_id = $self->{bugfix_request_id} = $params->{aru_no};

    my $work_area        = $preprocess->{work_area};
    my $aru_obj          = $preprocess->{aru_obj};
    my $ade              = $preprocess->{ade};
    my $transaction_name = $preprocess->{transaction_name};

    my ($pse, $blr, $utility_version) =
           ($preprocess->{pse}, $preprocess->{blr},
                            $preprocess->{bug_utility_version});

    $log_fh->print("Utility Version:\t$utility_version\n");

    $params->{action_desc} = 'Generate README';
    $log_fh->print_header($params->{action_desc});
    $params->{blr} = $blr;

    #
    # Generate README.txt file
    #
    my $readme_template =  "$ENV{ISD_HOME}/templates/PBuild/BEAReadme.tmpl";

    $preprocess->generate_readme($pse, $self->{output_dir},$readme_template);

    $params->{action_desc} = 'Build BEA Plugin';
    $log_fh->print_header($params->{action_desc});

    my $plugin = APF::PBuild::PluginBuild->new($aru_obj, $work_area,
                                               $log_fh, $pse, $blr,
                                               $transaction_name);
    my $script_name = "beabuild.sh";
    $plugin->build($script_name);

    $self->_postprocess($params);

    my $version =
          APF::PBuild::Util::get_version($utility_version);

    $plugin->release($aru_obj->{aru},$pse,$version);

    return;
}

sub _verify_platform_label
{
   my ($self, $params, $preprocess) = @_;

   #
   # below return is needed for the case when flow was back from the suspended
   # state , went to _preprocess and  then _preprocess called this method
   #
   return if(defined $params->{platform_label_ready});

   #
   # when _preprocess calls it, preprocess obj is passed
   # so we need not create the obj
   #
   if(not defined $preprocess)
   {
        $preprocess  = APF::PBuild::PreProcess->new($params);
   }

   my($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                                              $self->{request_id});
   if( $preprocess->verify_platform_label($params->{aru_no}) )
   {
      #
      # change the action type so that this method is called on resume
      #
      $req_params=~s/action:preprocess/action:verify_platform_label/i;
      ARUDB::exec_sp('isd_request.add_request_parameter',
                     $self->{request_id},
                     "st_apf_build",$req_params);
      my $current_time = scalar(localtime);
      $self->{aru_log}->print("\nCurrent time: $current_time\n");
      my $pf_label_wait_time = APF::Config::platform_label_wait_time;
      $self->suspend((delay=>$pf_label_wait_time));
  }
  else
  {
    #
    # Flag to denote snowball was suspended and now checkins are available
    #
    $params->{platform_label_ready}=1;

    if($req_params=~/action:verify_platform_label/i)
    {
     #
     # change action since checkins are ready.
     # no need to call this method on restart.
     # useful when the pbuild daemon is bounced.
     #
     $req_params=~s/action:verify_platform_label/action:preprocess/i;
     ARUDB::exec_sp('isd_request.add_request_parameter',
                    $self->{request_id},
                    "st_apf_build",$req_params);

     #
     # seems an issue in suspend api.it appends _<digit> to log filename in db
     # on resume. so on error it creates _<digit>.err file. but LogViewer
     # expects no digit in the .err file. So Logviewer cannot display the
     # requests which were suspended earlier and errored on resume.
     # Hence changing the filename key as a workaround.
     #
     my $request_log =
        $self->{aru_log}->get_task_log_info(format => "absolute");
     $request_log=~s/\.log$//;
     $self->{aru_log}->{filename}=$request_log;
     $self->_preprocess($params);
    }
    else
    {
       #
       # don't suspend since checkins are available on first try.
       #
       return;
    }
  }
}

sub _verify_active_snowball_patches
{
   my ($self, $params, $preprocess) = @_;

   #
   # below return is needed for the case when flow was back from the suspended
   # state , went to _preprocess and  then _preprocess called this method
   #
   return if(defined $params->{snowball_ready});

   #
   # when _preprocess calls it, preprocess obj is passed
   # so we need not create the obj
   #
   if(not defined $preprocess)
   {
        $preprocess  = APF::PBuild::PreProcess->new($params);
   }

   my($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                                              $self->{request_id});
   if( $preprocess->verify_active_snowball_patches($params->{aru_no}) )
   {
      #
      # Check if the transaction is set as NO_ARU_PATCH
      #
      my $ade_obj = new SrcCtl::ADE({no_die_on_error => 'YES'});
      my $txn_name;
      if($params->{txn_name})
      {
       $self->{aru_log}->print("\nTxn Name:$params->{txn_name}\n");
       $txn_name = $params->{txn_name};
      }
      else
      {
      $self->{aru_log}->print("Fetching Txn Name for aru:$params->{aru_no}\n");
      ($txn_name) = ARUDB::single_column_query('FETCH_TRANSACTION_NAME',
                                                  $params->{aru_no});
      $self->{aru_log}->print("Fetched Txn Name:$txn_name\n");
      }
      my $txn_no_aru_patch =
         $ade_obj->get_trans_property($txn_name,
                                      ARU::Const::trans_attrib_no_aru_patch);
      if ($txn_no_aru_patch =~ /^YES$/i)
      {
          $self->{aru_log}->print("\nTransaction property NO_ARU_PATCH " .
                                  "is set to YES. Halting patch build.\n");
          $self->{aru_log}->print_header("Patch Denied as NO ARU PATCH");
          $self->{aru_log}->print("Denying patch as transaction is " .
                                  "set to NO ARU PATCH\n");
          ARUDB::exec_sp('pbuild.update_empty_payload',
                         $params->{bug}, $params->{aru_no},
                         ARU::Const::patch_denied_no_aru_patch,
                         ARU::Const::apf2_userid,
                         "The transaction $txn_name is set as NO_ARU_PATCH",
                         ARU::Const::checkin_on_hold,
                         $preprocess->{release_id});
          $self->update_on_hold_bug_status($params->{bug});

          #
          # When a patch is dynamically set as NO_ARU_PATCH
          # we need to delete the seeded dependencies otherwise
          # these dependent bugs will affect upperwrapper metadata
          #
          my $aru_obj = $preprocess->{aru_obj};
          my ($txn_id) =
             ARUDB::exec_sf('aru.aru_transaction.get_transaction_id',
                            $aru_obj->{bugfix_id}, $params->{aru_no},
                            ['boolean', 0]);
          my ($basetxn_dos_seeded) =
             ARUDB::exec_sf('aru.aru_transaction.get_attribute_value',
                            $txn_id,
                            ARU::Const::trans_attrib_basetxn_seeded,
                            ['boolean', 0]);
          if ($basetxn_dos_seeded eq "YES")
          {
              $self->{aru_log}->print("\nDeleting seed data for ".
                                      "the transaction ..\n");
              ARUDB::exec_sp("aru.aru_object.delete_src_obj_data",
                             $params->{aru_no});
              ARUDB::exec_sp("aru_bugfix_bug_relationship.remove_relation",
                             $aru_obj->{bugfix_id}, ARU::Const::fixed_direct);
              ARUDB::exec_sp("aru_bugfix_bug_relationship.remove_relation",
                             $aru_obj->{bugfix_id}, ARU::Const::fixed_indirect);
              $self->{aru_log}->print("\nSeed data deleted successfully.\n\n");
              ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                             $txn_id,
                             ARU::Const::trans_attrib_basetxn_seeded,
                             'NO');
          }
          return;
      }

      #
      # change the action type so that this method is called on resume
      #
      $req_params=~s/action:preprocess/action:verify_active_snowball_patches/i;
      ARUDB::exec_sp('isd_request.add_request_parameter',
                     $self->{request_id},
                     "st_apf_build",$req_params);
      my $current_time = scalar(localtime);
      $self->{aru_log}->print("\nCurrent time: $current_time\n");
      my $snowball_wait_time = APF::Config::snowball_wait_time;
      $self->suspend((delay=>$snowball_wait_time));
  }
  else
  {
    #
    # Flag to denote snowball was suspended and now checkins are available
    #
    $params->{snowball_ready}=1;

    if($req_params=~/action:verify_active_snowball_patches/i)
    {
     #
     # change action since checkins are ready.
     # no need to call this method on restart.
     # useful when the pbuild daemon is bounced.
     #
     $req_params=~s/action:verify_active_snowball_patches/action:preprocess/i;
     ARUDB::exec_sp('isd_request.add_request_parameter',
                    $self->{request_id},
                    "st_apf_build",$req_params);

     #
     # seems an issue in suspend api.it appends _<digit> to log filename in db
     # on resume. so on error it creates _<digit>.err file. but LogViewer
     # expects no digit in the .err file. So Logviewer cannot display the
     # requests which were suspended earlier and errored on resume.
     # Hence changing the filename key as a workaround.
     #
     my $request_log =
        $self->{aru_log}->get_task_log_info(format => "absolute");
     $request_log=~s/\.log$//;
     $self->{aru_log}->{filename}=$request_log;
     $self->_preprocess($params);
    }
    else
    {
       #
       # don't suspend since checkins are available on first try.
       #
       return;
    }
  }
}

sub _test_snowball_dep_chkins
{
   my ($self, $params, $preprocess) = @_;

   my ($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                                              $self->{request_id});

   #
   # when _preprocess calls it, preprocess obj is passed
   # so we need not create the obj
   #
   if(not defined $preprocess)
   {
        $preprocess  = APF::PBuild::PreProcess->new($params);
   }

   if( $preprocess->test_snowball_dep_chkins($params->{aru_no}) )
   {
      my $delay ;
      my $retry_no ;
      my $retry_int = APF::Config::dep_checkin_retry_intervals;
      if( (not defined $params->{dep_checkin_retry_no}) ||
          ( (defined $params->{dep_checkin_retry_no}) &&
            (scalar(@$retry_int) == $params->{dep_checkin_retry_no}) ) )
      {
        $delay = $retry_int->[0];
        $retry_no = 1;
        $req_params .= '!DEP_CHECKIN_RETRY_NO:'.$retry_no;
      }
      else
      {
        $delay = $retry_int->[$params->{dep_checkin_retry_no}];
        $retry_no = $params->{dep_checkin_retry_no} + 1;
     $req_params=~s/!DEP_CHECKIN_RETRY_NO:\d+/!DEP_CHECKIN_RETRY_NO:$retry_no/;
      }

      ARUDB::exec_sp('isd_request.add_request_parameter', $params->{request_id},
                    "st_apf_build",$req_params);
      my $current_time = scalar(localtime);
      $self->{aru_log}->print("\nCurrent time: $current_time\n");
      $delay = 60 * $delay;
      $self->suspend((delay=>$delay));
  }
  else
  {
    $req_params=~s/!DEP_CHECKIN_RETRY_NO:\d+//;
    ARUDB::exec_sp('isd_request.add_request_parameter', $params->{request_id},
                    "st_apf_build",$req_params);

     my $request_log =
        $self->{aru_log}->get_task_log_info(format => "absolute");
     $request_log=~s/\.log$//;
     $self->{aru_log}->{filename}=$request_log;
     return;
   }
}

sub _run_fusion_portbuild
{

  my ($self,$preprocess,$params) = @_;

  $self->{aru_obj} = $preprocess->{aru_obj} if (! $self->{aru_obj});

  my $log_fh = $self->{aru_log};
  my $wkr;

  if (($self->{aru_obj}->{release_id} =~
       /^${\ARU::Const::applications_fusion_rel_exp}\d+$/) &&
       ($self->{aru_obj}->{platform_id} == ARU::Const::platform_generic) &&
       ($self->{aru_obj}->{language_id} == ARU::Const::language_US)) {

    my $requires_porting;
    ($requires_porting) =
            ARUDB::single_row_query('GET_BUGFIX_REQUIRES_PORTING_FLAG',
                             $self->{aru_obj}->{bugfix_id},
                             $self->{aru_obj}->{release_id});
    $requires_porting = "Y" if ($ENV{APF_DEBUG} =~ /REQUIRES_PORTING/);
    if ($requires_porting && ($requires_porting eq "Y")) {
      $self->{system} = $preprocess->{system};
      $self->_switch_aru_platform();
      $preprocess->{aru_obj} =  $self->{aru_obj};
    }
  }

  my $aru_obj = $self->{aru_obj};
  $aru_obj->get_details();

  my  $is_req_valid = 0;
  my ($config_type) =
      ARUDB::single_row_query("GET_REQUEST_CONFIG_TYPE",
                              $self->{request_id});
  if ($config_type eq ARU::Const::throttle_worker_type)
  {
      my ($apf_request_status) =
          ARUDB::single_row_query("IS_REQUEST_IN_PROGRESS",
                                  $self->{request_id},
                                  ISD::Const::isd_request_stat_busy,
                                  ARU::Const::fusion_group_id);

      if ($apf_request_status > 0)
      {
          $is_req_valid = 1;
      } else
      {
          $is_req_valid = 0;
      }
  }

  $log_fh->print_header("Port Platform Specific Files")
       if ($is_req_valid == 0);
  $params->{action_desc} = 'Port Platform Specific Files';

  my $bugfix_obj = $aru_obj->get_bugfix() if (! $aru_obj->{bugfix_obj} );
  if ($aru_obj->{bugfix_obj}->{requires_porting} eq 'No') {
      $log_fh->print("DEBUG: FATP Fusionapps txn : ".
                     $preprocess->{transaction_name}."\n");
      my ($is_fatp_file_set);
      if (defined APF::Config::enable_fatp_func &&
          APF::Config::enable_fatp_func == 1)
      {
          $self->{log_fh}->print("DEBUG: FATP functionality is enabled\n");
          my $txn_name = $preprocess->{transaction_name};
          ($is_fatp_file_set) =
              $preprocess->is_fatp_file_set_in_txn($txn_name);
      }

      if (defined $is_fatp_file_set &&  $is_fatp_file_set == 1)
      {
          $log_fh->print("DEBUG: FATP placeholder file is set in the ".
                         " transaction, So considering it for the ".
                         "Port Build \n");
      } else
      {
          $log_fh->print("Transaction does not have platform specific files " .
                         "to be built. Skipping port build\n");
          return;
      }
  }

  # Bug 27200081 - oversnowballing issues for 17.11/HCM
  # disable port build if no C-artifacts in direct DOs
  my ($product_family) = ARUDB::single_row_query('GET_PRODUCT_FAMILY',
                                                 $aru_obj->{release_id},
                                                 ARU::Const::direct_relation,
                                                 $aru_obj->{product});
  $log_fh->print("Product: " . $aru_obj->{product} . "\n" .
                 "Release: " . $aru_obj->{release_id} . "\n" .
                  "Product Family: " . $product_family . "\n");

   $log_fh->print("Utility version: " . $preprocess->{utility_version} . "\n");
   $log_fh->print("Base bug : " . $preprocess->{base_bug} . "\n");
   if ($preprocess->{utility_version} eq "11.13.17.11.0" &&
       $product_family eq "hcm")
   {
       $log_fh->print("Checking if transaction has platform specific files " .
                      "to be built.\n");
       my $direct_dos_fl = $preprocess->{work_area} . "/"  .
                           $preprocess->{base_bug} .  "_direct_dos.txt";
       $log_fh->print("Checking direct DOs file $direct_dos_fl\n");
       if ( -r "$direct_dos_fl")
       {
           my $sfl = new SimpleFileLoader($direct_dos_fl);
           my @lines = $sfl->get_lines();
           unless (grep(/^(bin|lib)/, @lines))
           {
               $log_fh->print("Transaction does not have platform specific ".
                              "files to be built in direct DOs. Skipping " .
                              "port build\n");
               return;
           }
       }
   }

  $self->{requires_porting} = 'Y';

  $wkr = APF::PBuild::PortBuild->new($aru_obj, $preprocess->{work_area},
                                        $log_fh, 0,
                                        $preprocess->{pse},
                                        $preprocess->{pse},
                                        $preprocess->{base_bug},
                                        $preprocess->{utility_version},
                                        "");

  $wkr->{isd_request_id} = $self->{request_id};
  $wkr->{throttle_req_type} = ARU::Const::throttle_build_type;
  $wkr->{type} = $preprocess->{type};
  if (defined $preprocess->{pse} && $preprocess->{pse} ne "")
  {
      $wkr->{pse_bug} = $preprocess->{pse};
  }
  else
  {
      $wkr->{pse_bug} = $preprocess->{bug};
  }

  $wkr->{request_id}  = $self->{request_id};
  $wkr->{preprocess}  = $self->{preprocess};
  $wkr->{user_id}     = $self->{params}->{user_id};
  $wkr->{config_file} = $self->{config_file};

  $wkr->{aru_no} = $aru_obj->{aru} ;
  $wkr->{fusion_port_build} = 1;
  $wkr->{generic_view_name} = $preprocess->{ade_view_name};
  $wkr->{base_prod_fam}     = $preprocess->{base_prod_fam};

  $wkr->init($aru_obj->{aru}) if ( !$wkr->{initialized} );

  if ((($aru_obj->{platform_id} != ARU::Const::platform_generic) &&
      ($aru_obj->{platform_id} != ARU::Const::platform_linux64_amd)) &&
       ($aru_obj->{language_id} == ARU::Const::language_US)) {
     my $platform_label =
         $preprocess->get_fusion_platform_label_name(
                                 $preprocess->{ade_view_label});
     $preprocess->{ade_view_label} = $platform_label->{name};
  }

  if($preprocess->is_fa_fetchtrans_enabled())
  {
   if($wkr->{port_txn_view})
   {
    $wkr->{view} = $wkr->{port_txn_view};
   }
   else
   {
    $wkr->{view}       = "$wkr->{aru_no}$$";
   }
   $wkr->{view_txn}   = "ptxn".$wkr->{aru_no}."_".$$;
  }
  else
  {
   $wkr->{view}       = "$wkr->{aru_no}$$";
  }

  $wkr->{view_label} = $preprocess->{ade_view_label};
  $log_fh->print("\n\nPlatform label :$wkr->{view_label}\n\n");
  $wkr->{build_type} = 'regular';
  $wkr->{view}       = "$wkr->{aru_no}$$";
  $wkr->{fusion_removed_files} = $preprocess->{fusion_removed_files};
  $wkr->{fusion_removed_dirs} = $preprocess->{fusion_removed_dirs};
  $log_fh->print("\n\nRemoved Files:$wkr->{fusion_removed_files}\n\n");
  $log_fh->print("\n\nRemoved Dirs:$wkr->{fusion_removed_dirs}\n\n");
  $wkr->{gen_port} = $preprocess->get_gen_port(
                                   $preprocess->{pse});
  $wkr->{bundle_type} =
            ARUDB::exec_sf('aru_bugfix_attribute.get_bugfix_attribute_value',
                           $self->{aru_obj}->{bugfix_id},
                           ARU::Const::group_patch_types);
  if ($wkr->{bundle_type})
  {
      $wkr->{bundle_txns_ts_map} = $preprocess->{bundle_txns_ts_map};
      $wkr->{base_prod_fam} = $aru_obj->{product};
      $wkr->{prod_fam_name} = $aru_obj->{product};
      ($wkr->{prod_fam_id}) = ARUDB::single_row_query("GET_PARENT_PRODUCT_ID",
                                                      $aru_obj->{product_id},
                                                      $aru_obj->{release_id});
  }

  my $skip_step_ts = "$preprocess->{work_area}/metadata/step/".
                     "fusion_port_build.ts";
  my $skip_step = 0;
  $skip_step = 1 if (-r "$skip_step_ts" && $preprocess->{type});
  unless ($skip_step == 1)
  {
      $wkr->validate_kerberos_fusion();

      if($preprocess->is_fa_fetchtrans_enabled())
      {

       #
       # identify if there is already a txn and an associated view
       #

       my $txn_tracker = $aru_obj->{bug}."_".
                   $self->{aru_obj}->{release_id}."_".
                   $aru_obj->{platform_id}."_".
                   $self->{aru_obj}->{language_id};
       my ($port_txn_view, $port_build_txn, $port_share_txn) =
           $preprocess->identify_view_txn_for_fa_ft($txn_tracker ,
                                             $wkr->{remote_ssh});
       $wkr->{port_txn_view} = $port_txn_view;
       $wkr->{port_build_txn} = $port_build_txn;
       $wkr->{port_share_txn} = $port_share_txn;

       $wkr->{enable_ftrans} = 1;
       $wkr->{fa_txn_tracker} = $txn_tracker;
       my $fetch_txn_list = "";

       #
       # Different txn list for bundle patch and snowball builds.
       #

       if($wkr->{bundle_type})
       {
        foreach my $key
                 (sort { $b <=> $a } keys %{$wkr->{bundle_txns_ts_map}})
        {
         $fetch_txn_list = $fetch_txn_list . "," .
                           $wkr->{bundle_txns_ts_map}->{$key};
        }
        $fetch_txn_list=~s/^,//;
       }
       else
       {
        $fetch_txn_list = $preprocess->{transaction_name} . "," .
                          $preprocess->{grabbed_txns};
       }
       $wkr->{fa_ftrans_list} = $fetch_txn_list;
      }

      $wkr->port_build($aru_obj->{aru},0,0,undef);
  }
  my $skip_step_fh = FileHandle->new("$skip_step_ts", 'w');
  $skip_step_fh->print(time);
  $skip_step_fh->close;

  $self->{prod_fam_id} = $wkr->{prod_fam_id};
  $log_fh->print("\n\nproduct family id:$self->{prod_fam_id}\n\n");
  $wkr->{fusion_port_build} = 0;
  return $wkr;
}

sub _contains_new_file
{
 my ($self, $txn_name) = @_;

 $self->{log_fh}->print("\nChecking if the current transaction includes ".
                        "new files ..\n");

 my $ade = new SrcCtl::ADE({no_die_on_error => 'YES'});
 $ade->get_transaction_metadata($txn_name);

 my $new_files_exist = (scalar(keys %{$ade->{transaction}->{NEW_FILES}})>0)?1
                                                                           :0;

 $self->{log_fh}->print("New Files exist in storage : $new_files_exist \n");

 unless($new_files_exist)
 {
  $self->{log_fh}->print("\nChecking new files info in ARU db\n");

  ($new_files_exist) = ARUDB::single_row_query("TXN_CONTAINS_NEW_FILES",
                                                $txn_name);

  $self->{log_fh}->print("New Files exist in db : $new_files_exist \n");
 }

 return $new_files_exist;
}


#
# Process the remaining steps in PreProcessing.
#
sub _preprocess
{
    my ($self, $params) = @_;

    my $bugfix_request_id = $self->{bugfix_request_id} = $params->{aru_no};
    my $preprocess  = APF::PBuild::PreProcess->new($params);
    my $is_autoport = 0;

    $self->{preprocess} = $preprocess;
    my $bug_aru_obj = new ARU::BugfixRequest($bugfix_request_id);
    $bug_aru_obj->get_details();

    $preprocess->{aru_obj} = $bug_aru_obj;

    $self->suspend_retry_request($params, $preprocess); # checks and suspends

    if ($params->{label})
    {
        my ($label, $type, $package, $from_label, $overwrite_version) =
            split('--',$params->{label});
        $params->{label}   =  $label;
        $params->{type}    =  $type;

        #
        # check for GIPSU bundles
        #
        my ($gipsu_subpatch) = ARUDB::exec_sf(
        'aru_parameter.get_parameter_value', 'GIPSU_SUBPATCH_LABELS');

        $params->{overwrite_version} =  $overwrite_version
            if ((defined $overwrite_version) && ($overwrite_version ne ""));

        eval{
        my $checkin_status = ARUDB::exec_sf_boolean('aru.aru_checkin.is_checkin_in_progress',
                                       $bug_aru_obj->{bugfix_id});
        my $bugfix_obj = new ARU::Bugfix("bugfix_id" => $bug_aru_obj->{bugfix_id});
        $bugfix_obj->get_head();
        $self->{aru_log}->print("Checkin status $checkin_status and Classification id: $bugfix_obj->{classification_id}\n");

        if ($checkin_status && $bugfix_obj->{classification_id} == ARU::Const::class_open)
        {
          $self->{aru_log}->print("Updating the classification id to internal\n");
          ARUDB::exec_sp("aru_checkin_admin.update_checkin_detail",
                             $bug_aru_obj->{bugfix_id}, 'classification_id',
                             ARU::Const::class_internal);
        }
        };

        $from_label =~ tr/a-z/A-Z/;
        $params->{from_label} =  $from_label;

        if ($type eq 'p4fa')
        {
            if ($label eq 'nolabel')
            {
                my $patches4fa = APF::PBuild::SystemPatch->new($params);
                $patches4fa->build($preprocess);
            }
            else
            {
                my $patches4fa = APF::PBuild::P4FA->new($params);
                $patches4fa->build($preprocess);
            }
        }
        elsif ($type eq 'systempatch')
        {
           my $patches4fa;
           if($params->{label} =~/META_DATA/i){
               $patches4fa = APF::PBuild::MetadataSystemPatch->new($params);
           }
           else{
               $patches4fa = APF::PBuild::SystemPatch->new($params);
           }
           $patches4fa->system_patch_build($preprocess);
           $patches4fa->{log_fh} = $self->{aru_log};
        }
        elsif ($type eq 'dated')
        {
            $preprocess->{params_label} = $params->{label};
        }
        elsif ($label =~ /$gipsu_subpatch/i)
        {
            my $bundlepatch    =  APF::PBuild::GIPSUBundlePatch->new($params);
            $self->{bundlepatch} = $bundlepatch;
            $bundlepatch->{bpr}  = $params->{bug};
            $bundlepatch->{log_fh} = $self->{aru_log};
            $bundlepatch->{package}    = $package;
            $bundlepatch->{bpr_label} = $params->{label};
            $bundlepatch->{bpr_type} = $type;
            $bundlepatch->{is_gipsu_subpatch} = 1;
            $preprocess->{is_gipsu_subpatch} = 1;
             $bundlepatch->{from_label} = $from_label;
            $preprocess->{from_label}  = $from_label;
            $bundlepatch->gipsu_build($preprocess);
        }
        else
        {
            my $bundlepatch;
            if($preprocess->is_meta_data_only_patch($params->{bug}, $params->{request_id})){
                $bundlepatch = APF::PBuild::MetadataBundlePatch->new($params);
            }
            else{
                $bundlepatch = APF::PBuild::BundlePatch->new($params);
            }
            $self->{bundlepatch} = $bundlepatch;
            $bundlepatch->{bpr}  = $params->{bug};
            $bundlepatch->{bpr_label} = $params->{label};
            $bundlepatch->{log_fh} = $self->{aru_log};
            $bundlepatch->{package}    = $package;
            $bundlepatch->{from_label} = $from_label;
            $bundlepatch->{sql_patch_only} = $params->{sql_patch_only};
            $preprocess->{from_label}  = $from_label;
            $bundlepatch->{overwrite_version} =  $overwrite_version
                if ((defined $overwrite_version) && ($overwrite_version ne ""));
            $preprocess->{overwrite_version} =  $overwrite_version
                if ((defined $overwrite_version) && ($overwrite_version ne ""));

            #
            # Build request
            #
            ARUDB::exec_sp("aru.apf_cd_patch_detail.insert_cd_patch_status",
                           $params->{bug},
                           'CD_REQUEST_ID',$params->{request_id});

            my $skip_header = $self->skip_header($params);

            if ($skip_header == 1)
            {
                $preprocess->{skip_header} = 1;
            }

            $bundlepatch->build($preprocess);
        }

        return;
    }

    my $bug = $params->{bug};
    #
    # check for category details
    #
    my ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component, $abstract, $transaction_name);

    if($self->{bugfix_request_id})
    {
        my ($patch_request) =
            ARUDB::single_row_query("GET_PSE_BUG_NO",
                                    $self->{bugfix_request_id});

        my ($rptno, $base_rptno, $comp_ver, $status, $version,
                     $port_id, $gen_or_port, $product_id, $category,
                     $sub_component, $customer, $version_fixed,
                     $test_name, $rptd_by)
                     = ARUDB::single_row_query("GET_BUG_DETAILS",
                                               $bug);
        if ((!$patch_request)
            && ($gen_or_port ne 'B')
            && ($gen_or_port ne 'M')
            && ($gen_or_port ne 'I')
            && ($gen_or_port ne 'Z'))
        {
            $is_autoport = 1;
            $bug = $self->{bugfix_request_id};
        }

    }


    if ($is_autoport == 1 &&
        ($preprocess->{aru_obj}->{release_id} =~
        /^${\ARU::Const::applications_fusion_rel_exp}\d+$/))
    {
        $bug = $preprocess->{pse};
        $is_autoport = 0;
    }


    ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component) =
            $preprocess->get_bug_details_from_bugdb($bug,$is_autoport);
    #
    # fork PCW process
    #
    my $clusterware_comp = PB::Config::clusterware_components;
    if ($category =~ /$clusterware_comp/i)
    {
        my $pcw = APF::PBuild::PCW->new($params);

        $pcw->{pse}  = $params->{bug};
        $pcw->{log_fh} = $self->{aru_log};

        $preprocess->preprocess($bugfix_request_id);
        $pcw->create_patch($preprocess);

        return;
    }

    $preprocess->is_fmw12c();
    #
    # Check for IDM stackpatch
    #
    my($is_stackpatch,$label)=$preprocess->is_stackpatch();
    if($is_stackpatch)
    {
        my $stackpatch = APF::PBuild::StackPatchBundle->new($params);
        $stackpatch->{log_fh} = $self->{aru_log};
        $stackpatch->{label} = $label;
        $self->{aru_log}->print("Processing Stack Patch Bundle\n\n");
        $stackpatch->stack_patch_build($preprocess);
        return;

    }
    #
    # for FMW12c process
    #
    if ($preprocess->{is_fmw12c})
    {
        my $fmw12c = APF::PBuild::FMW12c->new($params);

        $fmw12c->{pse} = $params->{bug};
        $fmw12c->{log_fh} = $self->{aru_log};

        my $orch_ref = APF::PBuild::OrchestrateAPF->new($params);
        $orch_ref->{log_fh} = $self->{aru_log};
        $orch_ref->{pse} = $params->{bug};
        $orch_ref->{utility_version} = $utility_ver;
        $orch_ref->{aru_obj} = $preprocess->{aru_obj};

        $orch_ref->post_fmw12c_data($params->{bug},"create_checkin",
                                    $params->{request_id},
                                    ISD::Const::st_apf_request_task);
        $fmw12c->create_patch($preprocess);
        return;
    }


    if (! defined APF::Config::enable_throttling_pse ||
        APF::Config::enable_throttling_pse != 1)
    {
        ARUDB::exec_sp("aru.apf_request_status.update_throttle_requests");
    }

    my $log_fh = $self->{aru_log};
    $preprocess->preprocess($bugfix_request_id);
    $self->{preprocess} = $preprocess;

    my $work_area        = $preprocess->{work_area};
    my $aru_obj          = $preprocess->{aru_obj};
    my $ade              = $preprocess->{ade};
    my $pse              = $preprocess->{pse};
    my $blr              = $preprocess->{blr};
    my $basebug          = $preprocess->{bug};
    my $ver              = $preprocess->{utility_version};
    my $base_bug         = $preprocess->{base_bug};
    my $transaction_name = $preprocess->{transaction_name};
    my $bugdb_prod_id    = $preprocess->{bugdb_prod_id};
    my $category         = $preprocess->{category};

    $self->{aru_obj} = $preprocess->{aru_obj} if (! $self->{aru_obj});

    #
    # For OBIEE and possibly the future, we are moving toward a non DOs
    # model. As such, this is the beginning of a different flow.
    #
    if (($self->is_bi_product($aru_obj->{product_id})) and
        ($aru_obj->{platform_id} != ARU::Const::platform_generic))
    {
        $log_fh->print_header("Run Farm Build Job")
            unless($self->skip_header($params));
        $params->{action_desc} = 'Run Farm Build Job';

        #
        # Check if there is already a farm build job running before creating
        # the view. Or else, the view will be forcefully refreshed and ruin the
        # current running job.
        #
        my ($job_id) =
        APF::PBuild::BI::Util::is_job_running($pse,
                                              $aru_obj->{platform_id},
                                              $aru_obj->{aru});

        if ($job_id)
        {
            $log_fh->print("\nFarm job $job_id is already running for this " .
                           "label. Please wait for build completion.\n\n");
            return;
        }

        #
        # Create the view with specific platform for farm build.
        #
        my $view_name = $ENV{USER} . "_local_" . $aru_obj->{aru};
        my $view_storage = PB::Config::ade_local_view_storage_loc;
        my $ade_obj = new SrcCtl::ADE({no_die_on_error => 'YES'});
        my $build_label =
          APF::PBuild::BI::Util::get_build_label(
                                     $preprocess->{transaction_label},
                                     $bugdb_platform_id);
        $ade_obj->set_filehandle($log_fh);
        $ade_obj->create_view($build_label,
                              $view_name,
                              (force => 'Y', view_storage => $view_storage));

        #
        # Run Farm build regardless of the platform.
        #
        my $farm_job = APF::PBuild::FarmJob->new(
                             {bugfix_req_id    => $aru_obj->{aru},
                              request_id       => $params->{request_id},
                              log_fh           => $log_fh,
                              bug              => $pse,
                              view_name        => $view_name,
                              transaction_name => $transaction_name,
                             });

        $farm_job->{label_name} = $build_label;
        $farm_job->submit_farm_build();

        #
        # In order to support other platforms, we need to leverage the
        # deliverables that are found by Linux/Generic build. As such, we
        # need to submit a Linux farm build.
        #
        if (($aru_obj->{platform_id} != ARU::Const::platform_linux) and
            ($aru_obj->{platform_id} != ARU::Const::platform_linux64_amd) and
            ($aru_obj->{platform_id} != ARU::Const::platform_generic))
        {
            $log_fh->print("BI: non Linux/Generic platform\n");
            $log_fh->print("BI: Base Bug: $preprocess->{base_bug}\n");
            $log_fh->print("BI: Release : $aru_obj->{release_id}\n");
            $log_fh->print("BI: Platform: $aru_obj->{platform_id}\n");

            #
            # Convert to Linux platform label and create the view.
            #
            $build_label = APF::PBuild::BI::Util::get_build_label(
                                      $build_label,
                                      ARU::Const::platform_linux64_amd);

            $view_name = $view_name . "_linux64";
            $ade_obj->create_view($build_label,
                                  $view_name,
                                  (force => 'Y',
                                   view_storage => $view_storage));

            #
            # Submit farm job for the Linux label.
            #
            $log_fh->print("BI: Build Label: $build_label\n");
            $log_fh->print("BI: View Name  : $view_name\n");
            $farm_job->{label_name} = $build_label;
            $farm_job->{view_name}  = $view_name;
            $farm_job->{view_name}  = $view_name;
            $farm_job->submit_farm_build(ARU::Const::platform_linux64_amd);
        }

        #
        # Return and wait for polling to pick up completion of the build.
        #
        return;
    }

    #
    # fix for 16202239, oms patches generated for
    # agent pses for em12c, need to get right
    # product_id agent or oms to get right release_id
    my ($em_product_id, $em_product_abbr) ;
    my ($release_name, $release_long_name, $release_id);
    if ($bugdb_prod_id == ARU::Const::product_bugdb_emgrid &&
        $ver =~ /12.1.0/)
    {
       ($em_product_id, $em_product_abbr) =
          $preprocess->get_em12c_product_details
            ($basebug, $ver,$bugdb_prod_id);
      $self->{em12c_product_id} = $em_product_id;
    }

    my $backport_online  =
        $preprocess->{transaction_details}->{BACKPORT_ONLINE_PATCH};

    my $backport_funclist =
        $preprocess->{transaction_details}->{BACKPORT_ONLINE_FUNC_LIST};

    #
    #  Error out when the transaction patch is not accessible by ADE
    #
    my $disable_trans_loc_err = APF::Config::disable_trans_loc_error;
    if ((defined $disable_trans_loc_err && $disable_trans_loc_err == 1) &&
        ($aru_obj->{release_id} =~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/) )
    {
        unless ($preprocess->{type})
    {
        if (defined $preprocess->{transaction_details}->{TRANS_NO_ACCESS} &&
            $preprocess->{transaction_details}->{TRANS_NO_ACCESS} ne "")
        {
            my $txn_error_msg = "Unable to access transaction path: ".
                       $preprocess->{transaction_details}->{TRANS_NO_ACCESS};
            die "$txn_error_msg \n";

        }
    }

    }

    my $buildinfo_fh ;
    my $tmpl_obj_text ;

    $bugfix_request_id         = $aru_obj->{aru};
    $self->{bugfix_request_id} = $bugfix_request_id;
    $self->{bugdb_prod_id}     = $bugdb_prod_id;

    my $gen_or_port = $preprocess->get_gen_port($pse);
    $gen_or_port = $preprocess->get_gen_port($preprocess->{base_bug})
        if (($gen_or_port eq "B") || ($gen_or_port eq "I") ||
            ($gen_or_port eq "Z"));

    #
    # If AutoPort Request
    #
    $gen_or_port = "O" if (!(defined($pse) && $pse ne ''));

    my $bundle_type  =
            ARUDB::exec_sf('aru_bugfix_attribute.get_bugfix_attribute_value',
                           $aru_obj->{bugfix_id},
                           ARU::Const::group_patch_types);
    my $skip_patch_build_feature_min_rel_id =
                    APF::Config::skip_patch_build_feature_min_rel_id;
    my $is_src_ctxn = 0;
    my $contains_new_files = 0;
    my $is_superseding_patch = 0;
    if ($aru_obj->{release_id} =~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/ &&
        $aru_obj->{language_id} == ARU::Const::language_US &&
        ($aru_obj->{platform_id} == ARU::Const::platform_generic ||
        $aru_obj->{platform_id} == ARU::Const::platform_linux64_amd) &&
        ! $bundle_type)
    {
        if ($aru_obj->{release_id} >= $skip_patch_build_feature_min_rel_id)
        {
            $log_fh->print("\nChecking if there are related skipped ".
                           "patches to the current patch ..\n");
            my @rel_skip_patches = ARUDB::query('GET_REL_SKIPPED_PATCHES',
                                                $base_bug,
                                                $aru_obj->{release_id});
            if (scalar(@rel_skip_patches) > 0)
            {
                $is_superseding_patch = 1;
                $log_fh->print("\nRelated skipped patches found in the ".
                               "branch for the current patch. Cannot ".
                               "validate this transaction for skip and ".
                               "parallel snowball features.\n");
            }

            $log_fh->print("\nChecking if the current transaction includes ".
                           "C source files ..\n");
            my $src_files = ARUDB::query('GET_SRC_LIST_FOR_TXN',
                                         $transaction_name);
            my $cfile_exts = APF::Config::skip_patch_cfile_exts;
            foreach my $src_files_row (@$src_files)
            {
                my $src_file_ext;
                my ($src_file) = @$src_files_row;
                $src_file_ext = $1 if ($src_file =~ /^\S+(\.\S+)$/);
                foreach my  $cfile_ext (split(/\|/, $cfile_exts))
                {
                    if($src_file_ext eq $cfile_ext)
                    {
                        $is_src_ctxn = 1;
                        $log_fh->print("\nCurrent transaction includes a C ".
                                       "source file (".$src_file."). Cannot ".
                                       "validate this transaction for skip ".
                                       "and parallel snowball features.\n\n");
                        last;
                    }
                }
                last if ($is_src_ctxn);
            }
          $contains_new_files = $self->_contains_new_file($transaction_name);
        }

        #
        # Defaulting values for enabling skip feature for all the cases
        # Retaining above code until skip feature stabilizes
        # Refer Bug# 25973922 for purpose.
        #
        $is_src_ctxn = 0;
        $contains_new_files = 0;
        $is_superseding_patch = 0;

        #
        # Skip feature is enabled only from release 11.1.5 and above.
        # This is a limitation of Src DO API given by FABUILD team.
        # Also we need to validate current transaction is not a C transaction,
        # in which case Src DO API will not return correct results.
        #
        my $parallel_snowball_feature_enabled =
            APF::Config::parallel_snowball_feature_enabled;
        my $skip_patch_feature_enabled =
            APF::Config::skip_patch_build_feature_enabled;

        if (!$is_superseding_patch && !$is_src_ctxn && !$contains_new_files &&
        !($preprocess->is_nls_bugfix_patch({bugfix_id=>$aru_obj->{bugfix_id}}))
           && $aru_obj->{release_id} >= $skip_patch_build_feature_min_rel_id &&
            ($parallel_snowball_feature_enabled || $skip_patch_feature_enabled))
        {
            my ($label_branch, $trans_merge_time, $non_snapshot_label);
            my ($seeding_status);
            my $ade_obj = new SrcCtl::ADE({no_die_on_error => 'YES'});

            my $base_label = $preprocess->{transaction_label};
            chomp($base_label);
            my $base_label_series;
            $base_label_series = $1 if ($base_label =~ /(\S+)_\S+/);

            #
            # Fetch the branch from label metadata
            #
            $label_branch =
                $ade_obj->get_label_metadata($base_label, "AUTO_MAKEBRANCH");
            $label_branch = $1 if ($label_branch =~ /\S+\/(\S+)/);
            $log_fh->print("Label branch - $label_branch \n");
            die ("Unable to fetch label branch. Cannot proceed. \n")
                if ($label_branch eq "");

            #
            # Fetch transaction merge time
            #
            my @arry = ($transaction_name,
                        {
                          name  => 'pb_raise_exception',
                          data   => 0,
                          type   => 'boolean'
                        });
            ($trans_merge_time) =
                ARUDB::exec_sf('aru.pbuild.get_transaction_merge_time',
                               @arry);
            $log_fh->print("Transaction Merge Time - $trans_merge_time\n");
            if ($trans_merge_time eq "")
            {
                ($trans_merge_time) =
                    ARUDB::single_row_query("GET_TXN_MERGE_TIME",
                                            $transaction_name);
                $log_fh->print("Transaction Merge Time upon retry - ".
                               $trans_merge_time ."\n");
            }
            # Sometimes one retry isn't enough. we retry twice
            if ($trans_merge_time eq "")
            {
                ($trans_merge_time) =
                    ARUDB::single_row_query("GET_TXN_MERGE_TIME",
                                            $transaction_name);
                $log_fh->print("Transaction Merge Time upon retry #2 - ".
                               $trans_merge_time ."\n");
            }
            die ("Unable to fetch transaction merge time. Cannot proceed. \n")
                if ($trans_merge_time eq "");

            #
            # Fetch non snapshot label
            #
            $non_snapshot_label =
               ARUDB::exec_sf(
                       "aru.aru_bugfix_attribute.get_bugfix_attribute_value",
                       $aru_obj->{bugfix_id},
                       ARU::Const::fusion_non_snapshot_label);
            if ($non_snapshot_label ne "")
            {
                $log_fh->print("Verifying if NO_ARU_LABEL property is ".
                               "set in label $non_snapshot_label ..\n");
                my $non_snapshot_label_details =
                    $preprocess->_get_ade_label_details($non_snapshot_label);
                $non_snapshot_label = ""
                    if (defined $non_snapshot_label_details->{NO_ARU_LABEL});
            }
            if ($non_snapshot_label eq "" and
                $aru_obj->{language_id} == ARU::Const::language_US and
                ($aru_obj->{platform_id} ==
                 ARU::Const::platform_generic or
                 $aru_obj->{platform_id} ==
                 ARU::Const::platform_linux64_amd))
            {
                $non_snapshot_label =
                    $preprocess->_get_non_snapshot_label($base_label,
                                                         $base_label_series,
                                                         $label_branch,
                                                         $trans_merge_time);
            }
            die ("Unable to fetch non snapshot label. Cannot proceed. \n")
               if ($non_snapshot_label eq "");
            ARUDB::exec_sp("aru.aru_bugfix_attribute.set_bugfix_attribute",
                           $aru_obj->{bugfix_id},
                           ARU::Const::fusion_non_snapshot_label,
                           $non_snapshot_label);
            $log_fh->print("Non-snapshot label - $non_snapshot_label \n");

            #
            # Check if current transaction seeding is already done.
            #
            $log_fh->print("\nChecking if seed data is available for ".
                           "current transaction $transaction_name ..\n");
            my $seeding_reqd = 1;
            my ($txn_id) =
                ARUDB::exec_sf('aru.aru_transaction.get_transaction_id',
                               $aru_obj->{bugfix_id}, $bugfix_request_id,
                               ['boolean', 0]);
            my ($basetxn_dos_seeded) =
                ARUDB::exec_sf('aru.aru_transaction.get_attribute_value',
                               $txn_id,
                               ARU::Const::trans_attrib_basetxn_seeded,
                               ['boolean', 0]);
            if ($basetxn_dos_seeded eq "YES")
            {
                $log_fh->print("\nSeed data is already available for ".
                               "current transaction. Checking if there ".
                               "is a change in status for any of the ".
                               "included bugs..\n");
                my $incl_bugs = ARUDB::query('GET_INCLUDED_BUGS',
                                             $aru_obj->{bugfix_id});
                my $change_in_status = 0;
                foreach my $included_bug (@$incl_bugs)
                {
                    $log_fh->print("Checking included bug: ".
                                   $included_bug->[1]."\n");
                    my ($checkin_status, $patch_status,$chkin_id) =
                        ARUDB::single_row_query('GET_CHECKIN_STATUS',
                                                $included_bug->[1],
                                                $aru_obj->{release_id},
                                                APF::Config::lang_code);
                    my $exclude_from_snowball = ARUDB::exec_sf(
                        "aru.aru_bugfix_attribute.get_bugfix_attribute_value",
                        $chkin_id, ARU::Const::fusion_exclude_from_snowball);
                    if ($checkin_status == ARU::Const::checkin_obsoleted ||
                        $patch_status   == ARU::Const::patch_deleted ||
                        $exclude_from_snowball eq "YES")
                    {
                        $log_fh->print("Change in status detected for ".
                                       "included bug: ".
                                       $included_bug->[1]."\n");
                        $change_in_status = 1;
                        last;
                    }
                }

                if ($change_in_status)
                {
                    $log_fh->print("Reseeding required for current ".
                                   "transaction as some of the included ".
                                   "bug(s) have changed status in ARU.\n");
                }
                else
                {
                    $seeding_reqd = 0;
                    $seeding_status = 0;
                    $log_fh->print("Seed data change not required ".
                                   "for current transaction.\n");
                }
            }

            if ($seeding_reqd)
            {
                $log_fh->print("\nChecking for source dos ..\n");
                my ($directdos_seeded) = ARUDB::single_row_query(
                                             'IS_DIRECTDOS_SEEDED',
                                             $transaction_name);
                ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                               $txn_id,'SRCDOS_SEEDED_AT_MERGE','NO')
                    unless $directdos_seeded;
                $log_fh->print("\nSeeding data for current transaction ..\n");
                my ($product_id, $product_abbr) =
                    APF::PBuild::Util::get_aru_product_id($bugdb_prod_id,$ver);
                $seeding_status =
                    $preprocess->_seed_dos_for_base_txn($transaction_name,
                                                        $base_bug,
                                                        $label_branch,
                                                        $trans_merge_time,
                                                        $product_abbr,
                                                        $aru_obj->{release_id},
                                                        $bugfix_request_id);
            }

            if ($seeding_status)
            {
                $log_fh->print("\nSeeding data for current transaction ".
                               "did not complete successfully.\n\n");
                $log_fh->print("\nDeleting partially seeded data for ".
                               "the transaction ..\n\n");
                ARUDB::exec_sp("aru.aru_object.delete_src_obj_data",
                               $bugfix_request_id);
                ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                               $txn_id,
                               ARU::Const::trans_attrib_basetxn_seeded,
                               'NO');
            }
            else
            {
                #
                # Set trans_attrib_basetxn_seeded attribute to YES
                #
                ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                               $txn_id,
                               ARU::Const::trans_attrib_basetxn_seeded,
                               'YES');

                if (($gen_or_port eq "G") || ($gen_or_port eq "P"))
                {
                    my $txn_allow_skip_patch =
                        $ade_obj->get_trans_property($transaction_name,
                            ARU::Const::trans_attrib_allow_skip_patch);
                    my $forced_rebuild =
                        ARUDB::exec_sf(
                        "aru.aru_bugfix_attribute.get_bugfix_attribute_value",
                        $aru_obj->{bugfix_id},
                        ARU::Const::fusion_force_rebuild);
                    my ($is_replacement_patch, $base_patch) =
                        ARUDB::single_row_query(
                            "CHECK_IF_REPLACEMENT_PATCH",
                            $aru_obj->{release_id}, $base_bug);
                    if ($txn_allow_skip_patch =~ /^NO$/i &&
          $aru_obj->{release_id} < APF::Config::fawide_patching_min_rel_id)
                    {
                        $log_fh->print("\nTransaction property ".
                                       "FUSION_ALLOW_SKIP_PATCH ".
                                       "is set to NO. Forcing ".
                                       "complete patch build.\n");
                        $log_fh->print("\nDeleting seed data for ".
                                       "the transaction ..\n\n");
                        ARUDB::exec_sp("aru.aru_object.delete_src_obj_data",
                                       $bugfix_request_id);
                        $log_fh->print("\nSeed data deleted successfully.\n\n");
                        ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                                       $txn_id,
                                       ARU::Const::trans_attrib_basetxn_seeded,
                                       'NO');
                    }
                    elsif($forced_rebuild =~ /^YES$/i)
                    {
                        $log_fh->print("\nBugfix Attribute ".
                                       ARU::Const::fusion_force_rebuild.
                                       "is set to YES. ".
                                       "Forcing complete patch build.\n");
                        $log_fh->print("Removing skip patch info ".
                                       "from patch supersedures.\n");
                        ARUDB::exec_sp(
                            "aru.apf_patch_supersedure.handle_skip_patch_rereq",
                                $aru_obj->{bugfix_id});
                        $log_fh->print("\nDeleting seed data for ".
                                       "the transaction ..\n\n");
                        ARUDB::exec_sp("aru.aru_object.delete_src_obj_data",
                                       $bugfix_request_id);
                        $log_fh->print("\nSeed data deleted successfully.\n\n");
                        ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                                       $txn_id,
                                       ARU::Const::trans_attrib_basetxn_seeded,
                                       'NO');
                    }
                    elsif($is_replacement_patch)
                    {
                        $log_fh->print("\nPatch $base_bug is marked as a ".
                                       "replacement patch for $base_patch. ".
                                       "Forcing complete patch build.\n");
                        $log_fh->print("\nDeleting seed data for ".
                                       "the transaction ..\n\n");
                        ARUDB::exec_sp("aru.aru_object.delete_src_obj_data",
                                       $bugfix_request_id);
                        $log_fh->print("\nSeed data deleted successfully.\n\n");
                        ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                                       $txn_id,
                                       ARU::Const::trans_attrib_basetxn_seeded,
                                       'NO');
                    }
                    else
                    {
                        #
                        # Verify patch skip criteria
                        #
                        if ($skip_patch_feature_enabled)
                        {
                            my ($req_params) =
                                ARUDB::single_row_query('GET_ST_APF_BUILD',
                                                        $self->{request_id});
                            if ($req_params !~ /skipval_delay_done:YES/i)
                            {
                                $log_fh->print("\nVerifying if delay is set ".
                                               "for skip validation..\n");
                                my $skip_feature_delay =
                                    APF::Config::skip_patch_build_feature_delay;
                                if ($skip_feature_delay > 0)
                                {
                                    $log_fh->print("Suspending skip ".
                                                   "validation for ".
                                                   $skip_feature_delay .
                                                   " min(s).\n");
                                    my $skip_delay_in_min =
                                         $skip_feature_delay * 60;
                                    my $skipval_req_param = $req_params .
                                         "!"."skipval_delay_done:YES";
                                    ARUDB::exec_sp(
                                       'isd_request.add_request_parameter',
                                       $self->{request_id},"st_apf_build",
                                       $skipval_req_param);
                                    my $current_time = scalar(localtime);
                                    $log_fh->print("\nCurrent time: ".
                                                   $current_time."\n");
                                    $self->suspend((delay=>
                                                    $skip_delay_in_min));
                                }
                            }

                            $log_fh->print("\nChecking if there are ".
                                           "related skipped patches to ".
                                           "current patch $base_bug ..\n");
                            my @rel_skip_patches =
                                ARUDB::query('GET_REL_SKIPPED_PATCHES',
                                             $base_bug,
                                             $aru_obj->{release_id});
                            if (scalar(@rel_skip_patches) > 0)
                            {
                                $log_fh->print("Found patches that are ".
                                    "skipped based on current patch.\n");
                                my $incl_skip_patch = 0;
                                foreach my $skip_patches(@rel_skip_patches)
                                {
                                    # Verify if the skipped patch is
                                    # included in the current patch
                                    my ($skip_patch, $skip_patch_bugfix) =
                                        @$skip_patches;
                                    my $incl_bugs = ARUDB::query(
                                        'GET_INCLUDED_BUGS',
                                        $aru_obj->{bugfix_id});
                                    foreach my $incl_bug (@{$incl_bugs})
                                    {
                                        $incl_skip_patch = 1
                                            if ($incl_bug->[1] == $skip_patch);
                                    }
                                    if (!$incl_skip_patch)
                                    {
                                        my $err_msg = "Related skipped ".
                                          "patch $skip_patch is not ".
                                          "included in the current patch. ".
                                          "Since this will affect ".
                                          "snowballing, current patch ".
                                          "build cannot proceed.\n";
                                        $err_msg .= "Full build for ".
                                          "related skipped patches ".
                                          "and build for current failed ".
                                          "patch will be automatically ".
                                          "re-requested by ARU.\n";
                                        $log_fh->print($err_msg);
                                        $log_fh->print("\nDeleting seed ".
                                          "data for the transaction ..\n");
                                        ARUDB::exec_sp(
                                          "aru.aru_object.delete_src_obj_data",
                                          $bugfix_request_id);
                                        $log_fh->print("\nSeed data ".
                                          "deleted successfully.\n\n");
                                        ARUDB::exec_sp(
                                          "aru.aru_transaction.add_attribute",
                                          $txn_id,
                                      ARU::Const::trans_attrib_basetxn_seeded,
                                          'NO');
                                        my $disable_skipval_bug_updates =
                                      APF::Config::disable_skipval_bug_updates;
                                        ARUDB::exec_sp(
                                          'bugdb.async_create_bug_text',
                                          $params->{bug}, $err_msg)
                                            if(! $disable_skipval_bug_updates);
                                   $preprocess->handle_relskip_patch_forcebuild(
                                          $base_bug, $aru_obj->{release_id},
                                          $err_msg);
                                    }
                                }
                            }

                            $log_fh->print("\nVerifying patch skip ".
                                           "criteria ..\n");
                            my ($ret_status, $skip_status,
                                $skip_msg, $SS_patch);

                            #
                            # overriding skip status if new files found
                            # in the txn.
                            #
                            # Disabling this validation for bug 25973922
                            # Will remove code after skip feature
                            # stabilizes
                            #
                            # $ade_obj->get_transaction_metadata(
                            #                     $transaction_name);
                            # if(
                            # keys %{$ade_obj->{transaction}->{NEW_FILES}} >= 1)
                            # {
                            #     $skip_status = 0;
                            # }
                            # else
                            # {
                            $ret_status =
                                $preprocess->verify_patch_skip_criteria(
                                                    $params,
                                                    $non_snapshot_label,
                                                    $label_branch,
                                                    $trans_merge_time,
                                                    $aru_obj->{release_id});
                            ($skip_status, $skip_msg, $SS_patch) =
                                                    @{$ret_status};
                            # }

                            if ($skip_status)
                            {
                                $log_fh->print_header("Patch build skipped");
                                $log_fh->print($skip_msg . "\n");
                                $log_fh->print("Checking for previous ".
                                               "on-hold ARUs ..\n");
                                my $oh_arus = ARUDB::query('GET_ONHOLD_ARU',
                                              $preprocess->{base_bug},
                                              $aru_obj->{release_id});
                                foreach my $oh_aru(@$oh_arus)
                                {
                                    $log_fh->print("Deleting on-hold ARU ".
                                                   $oh_aru->[1]."\n");
                                    ARUDB::exec_sp("apf_queue.update_aru",
                                                   $oh_aru->[1],
                                                   ARU::Const::patch_deleted,
                                                   'Deleting on-hold ARU.');
                                }
                                ARUDB::exec_sp(
                                    'pbuild.update_empty_payload',
                                    $preprocess->{base_bug},$aru_obj->{aru},
                                    ARU::Const::patch_skipped,
                                    ARU::Const::apf2_userid, $skip_msg,
                                    ARU::Const::checkin_on_hold,
                                    $aru_obj->{release_id});
                                my $disable_skipval_bug_updates =
                                    APF::Config::disable_skipval_bug_updates;
                                $skip_msg .= "\nTest the current bugfix ".
                                    "through the superset patch (".$SS_patch.
                                    ") and update this bug following the ".
                                    "usual process.\n";
                                ARUDB::exec_sp (
                                    'bugdb.async_create_bug_text',
                                            $params->{bug}, $skip_msg)
                                    if(! $disable_skipval_bug_updates);
                                $log_fh->print("\nTerminating patch ".
                                               "build process.\n");
                                return;
                            }
                        }
                        else
                        {
                            $log_fh->print("\nSkip patch build feature ".
                                   "is disabled for this request. Patch ".
                                   "build for this transaction will ".
                                   "continue without validating for ".
                                   "skip feature.\n\n");
                        }
                    }
                }
            }
        }

        if ((($aru_obj->{platform_id} != ARU::Const::platform_generic) &&
         ($aru_obj->{platform_id} != ARU::Const::platform_linux64_amd)) &&
         ($aru_obj->{language_id} == ARU::Const::language_US))
        {
           $self->_verify_platform_label($params,$preprocess);
        }

        $gen_or_port =
                $preprocess->get_gen_port($preprocess->{base_bug})
                    if (($gen_or_port eq "B") || ($gen_or_port eq "I") ||
                        ($gen_or_port eq "Z"));
        if (($gen_or_port eq "G") || ($gen_or_port eq "P"))
        {
             $self->_verify_active_snowball_patches($params,$preprocess);
        }

        #
        # Delete seed data created for the transaction
        # if the skip validations are disabled
        #
        my ($txn_id) =
            ARUDB::exec_sf('aru.aru_transaction.get_transaction_id',
                           $aru_obj->{bugfix_id}, $aru_obj->{aru},
                           ['boolean', 0]);
        my ($basetxn_dos_seeded) =
            ARUDB::exec_sf('aru.aru_transaction.get_attribute_value',
                           $txn_id,
                           ARU::Const::trans_attrib_basetxn_seeded,
                           ['boolean', 0]);
        if ($basetxn_dos_seeded eq "YES" && !$skip_patch_feature_enabled)
        {
            $log_fh->print("\nDeleting seed data for the transaction ".
                           "since skip validations are disabled..\n");
            ARUDB::exec_sp("aru.aru_object.delete_src_obj_data",
                           $aru_obj->{aru});
            $log_fh->print("\nSeed data deleted successfully.\n\n");
            ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                           $txn_id,
                           ARU::Const::trans_attrib_basetxn_seeded,
                           'NO');
        }

        #
        # Check if the transaction is set as NO_ARU_PATCH
        #
        my $ade_obj = new SrcCtl::ADE({no_die_on_error => 'YES'});
        my $txn_no_aru_patch =
           $ade_obj->get_trans_property($transaction_name,
                                        ARU::Const::trans_attrib_no_aru_patch);
        if ($txn_no_aru_patch =~ /^YES$/i)
        {
            $log_fh->print("\nTransaction property NO_ARU_PATCH " .
                           "is set to YES. Halting patch build.\n");
            $log_fh->print_header("Patch Denied as NO ARU PATCH");
            $log_fh->print("Denying patch as transaction is " .
                           "set to NO ARU PATCH\n");
            ARUDB::exec_sp('pbuild.update_empty_payload',
                           $preprocess->{base_bug}, $aru_obj->{aru},
                           ARU::Const::patch_denied_no_aru_patch,
                           ARU::Const::apf2_userid,
                           "The transaction $preprocess->{transaction_name} ".
                           "is set as NO_ARU_PATCH",
                           ARU::Const::checkin_on_hold,
                           $aru_obj->{release_id});
            $self->update_on_hold_bug_status($preprocess->{base_bug});

            #
            # When a patch is dynamically set as NO_ARU_PATCH
            # we need to delete the seeded dependencies otherwise
            # these dependent bugs will affect upperwrapper metadata
            #
            if ($basetxn_dos_seeded eq "YES")
            {
                $log_fh->print("\nDeleting seed data for the transaction ..\n");
                ARUDB::exec_sp("aru.aru_object.delete_src_obj_data",
                               $aru_obj->{aru});
                ARUDB::exec_sp("aru_bugfix_bug_relationship.remove_relation",
                               $aru_obj->{bugfix_id}, ARU::Const::fixed_direct);
                ARUDB::exec_sp("aru_bugfix_bug_relationship.remove_relation",
                             $aru_obj->{bugfix_id}, ARU::Const::fixed_indirect);
                $log_fh->print("\nSeed data deleted successfully.\n\n");
                my ($txn_id) =
                 ARUDB::exec_sf('aru.aru_transaction.get_transaction_id',
                                $aru_obj->{bugfix_id}, $aru_obj->{aru},
                                ['boolean', 0]);
                ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                               $txn_id,
                               ARU::Const::trans_attrib_basetxn_seeded,
                               'NO');
            }
            return;
        }
    }

    #
    # Invoke the FD integration tool flow.
    #
    my $product_id = $self->{aru_obj}->{product_id} || $self->{product_id};
    my $utility_version = $preprocess->{utility_version}
                              || $self->{aru_obj}->{utility_version}
                              || $self->{utility_version};
    $utility_version =~ m/(\d+).(\d+).(\d+).(\d+).(\d+).*/;
    $self->{bugdb_prod_id} =  $self->{bugdb_prod_id} || $preprocess->{bugdb_prod_id};
    my $version = "$1$2$3$4";


    my $rel_id = $self->{aru_obj}->{release_id}
                  || $self->{release_id}
                  || $preprocess->{release_id};
    my $isPSU = ARUDB::exec_sf_boolean('aru.pbuild.is_psu_release',
                                       $rel_id);

    my $fmw11g_enable_fd_tool = ARUDB::exec_sf("aru_parameter.get_parameter_value",
                                             "fmw11g_enable_fd_tool");
    my $fmw11g_hash_enabled;

    eval '$fmw11g_hash_enabled'. " = $fmw11g_enable_fd_tool;";

    my $fmw11g_enabled_version = $fmw11g_hash_enabled->{$product_id};


    if ($fmw11g_hash_enabled->{$product_id} && $version =~ /$fmw11g_enabled_version/
        && $isPSU)
    {

        $log_fh->print("Invoking FD integration tools... $version\n");
        $params->{log_fh} = $self->{aru_log};
        $params->{request_id} = $self->{request_id};
        $params->{preprocess} = $preprocess;

        $params->{log_fh} = $self->{aru_log};
        $params->{request_id} = $self->{request_id};
        $params->{preprocess} = $preprocess;

        my $fmw11g;

        $fmw11g        =  APF::PBuild::FMW11g->new($params);
        $fmw11g->{pse} = $params->{bug};
        $fmw11g->{log_fh}     = $self->{aru_log};
        $fmw11g->{product_id} = $self->{aru_obj}->{product_id} || $self->{product_id};
        $fmw11g->{release_id} = $rel_id ;

        $fmw11g->{base_bug}  = $preprocess->{base_bug};
        $fmw11g->{utility_version} = $preprocess->{utility_version}
                                     || $self->{aru_obj}->{utility_version}
                                     || $self->{utility_version};
        $log_fh->print_header("Request PSE: $params->{bug} \n");
        $fmw11g->create_patch();
        return;
    }

    #
    # Run GSCC
    #
    if ($aru_obj->{release_id} !~
        /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        if($self->skip_header($params))
        {
            my ($is_patch_released) = ARUDB::single_row_query
                                        ('IS_PATCH_RELEASED',
                                         $aru_obj->{aru});

            if ($is_patch_released == 1)
            {
                $log_fh->print("DEBUG: Patch is already released to".
                               " the customer \n");
                return;
            }

        }

        $params->{action_desc} = 'Running GSCC';
        $log_fh->print_header($params->{action_desc})
            unless($self->skip_header($params));
        $self->_run_gscc($transaction_name, $aru_obj,
                         $preprocess->{transaction_label});
    }

    my ($aru_comment) =
        ARUDB::single_row_query('GET_ARU_REQUEST_COMMENT',
                                $aru_obj->{aru});

    my @aru_comments  = split(/\|/, $aru_comment);
    my @pbuild_params = split(':',$aru_comments[1]);

    $self->{$pbuild_params[0]}     = $pbuild_params[1];
    $self->{lc($pbuild_params[0])} = lc($pbuild_params[1]);

    $self->{req_id} = $self->{request_id}
        if ($aru_obj->{language_id} != ARU::Const::language_US);

    #
    # If Auto Port request,make action as request.
    #
    $self->{action} = 'request' if ((!(defined($pse) && $pse ne '')) ||
                                            $aru_comment eq 'Auto Port');

    #
    # Updating ABRH table for tracking auto port requests using
    # request_id.
    #
    ARUDB::exec_sp("aru_request.insert_history",
                   $aru_obj->{aru},
                   ARU::Const::apf2_userid,
                   ISD::Const::st_apf_preproc,
                   "Auto Port Request id $self->{request_id}")
             if (((!(defined($pse) && $pse ne ''))) ||
                 (($aru_comment eq 'Auto Port') &&
                    ($aru_obj->{release_id} =~
                       /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)));

    my ($request_param_value) =
        ARUDB::single_row_query('GET_ST_APF_BUILD',
                                $self->{req_id});

    foreach my $i (split('!',$request_param_value))
    {
        my ($key, $value) = split(':',$i);
        $self->{$key} = $value;
        $self->{lc($key)} = lc($value);
    }

    #
    # BEA Plugin
    #

    if ($bugdb_prod_id == ARU::Const::product_bugdb_beaowls) {
      $self->_process_beaplugin($params);
      return;
    }

    $aru_obj->{txn_label} = $preprocess->{transaction_label};
    if (! defined $preprocess->{aru_obj}->{backport_info}->{rptno})
    {
        my $backport_info_bug =
            $aru_obj->{backport_info}->{rptno};
        $preprocess->{aru_obj}->{$backport_info_bug} =
            $aru_obj->{$backport_info_bug};
        $preprocess->{aru_obj}->{backport_info} =
            $aru_obj->{backport_info};
    }

    $self->{skip_header} = 1;
    unless ($self->skip_header($params))
    {
           $self->{skip_header} = 0;
    }

    my $is_req_valid = 0;
    if ($aru_obj->{release_id} =~
        /^${\ARU::Const::applications_fusion_rel_exp}\d+$/ &&
        $self->{skip_header} == 1)
    {
        my ($config_type) =
            ARUDB::single_row_query("GET_REQUEST_CONFIG_TYPE",
                                    $self->{request_id});
        if ($config_type eq ARU::Const::throttle_worker_type)
        {
        my ($apf_request_status) =
            ARUDB::single_row_query("IS_REQUEST_IN_PROGRESS",
                                    $self->{request_id},
                                    ISD::Const::isd_request_stat_busy,
                                    ARU::Const::fusion_group_id);

        if ($apf_request_status > 0)
        {
            $is_req_valid = 1;
            $log_fh->print("DEBUG: Skipping the Platform Independent Build".
                           " as it has re-submitted into queue, due ".
                           " to unavailablity of the resource for Port".
                           " build\n");
        } else
        {
            $is_req_valid = 0;
        }
    }
    }

    $log_fh->print("DEBUG: ARU PSE : $preprocess->{aru_obj}->{ARU_PSE_BUG},".
                   "$aru_obj->{ARU_PSE_BUG} \n");
    my ($patch_type) = ARUDB::single_row_query('GET_BUGFIX_PATCH_TYPE',
                                                   $aru_obj->{bugfix_id});
    if ($self->{action} eq "request" ||
        ($self->{action} eq "preprocess" &&
         ($aru_obj->{language_id} != ARU::Const::language_US)))
    {
        $params->{action_desc} = 'Platform Independent Build';
        $log_fh->print_header($params->{action_desc})
            unless($self->skip_header($params));

        my $generic_port = APF::PBuild::GenericBuild->new($aru_obj,
                                                          $aru_obj->{aru},
                                                          $work_area, $log_fh);
        $generic_port->{isd_request_id} = $self->{request_id};
        $generic_port->{request_id} = $self->{request_id};

        $preprocess->{isd_request_id} = $self->{request_id};
        $preprocess->{request_id} = $self->{request_id};

        if ($aru_obj->{release_id} =~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
        {
            $preprocess->{skip_ind_build_step} = 0;
            if ($is_req_valid == 1)
            {
                $preprocess->{skip_ind_build_step} = 1;
                $log_fh->print("DEBUG: Skipping the Platform ".
                               "Independent Build\n");
            }
            # In case of Fusion backport we need to use G/P of base bug
            $gen_or_port =
                $preprocess->get_gen_port($preprocess->{base_bug})
                    if (($gen_or_port eq "B") || ($gen_or_port eq "I") ||
                        ($gen_or_port eq "Z"));
            $preprocess->{system}->do_mkdir("$work_area/metadata/step");
            my $skip_step_ts = "$work_area/metadata/step/".
                               "fusion_snowball_build.ts";
            my $skip_step = 0;
            $skip_step = 1 if (-r "$skip_step_ts" &&
                          $aru_obj->{language_id} == ARU::Const::language_US);

            # Default G/P flag to 'G' for NLS bundles as this is now stored in
            # aru_bugfix_attributes during US patch build - not applicable
            # for bundles since ant patch is not invoked
            $gen_or_port = 'G'
                 if ($aru_obj->{language_id} != ARU::Const::language_US &&
                     ($patch_type == ARU::Const::ptype_merged ||
                      $bundle_type =~ /merged/i));
            $log_fh->print("G/P flag: $gen_or_port\n");

            if (($gen_or_port eq "G") || ($gen_or_port eq "P"))
            {
                unless ($patch_type == ARU::Const::ptype_merged ||
                        $bundle_type =~ /merged/i)
                {
                $preprocess->run_fusion_snowball_build($bugfix_request_id,
                                                       $skip_step);
                }
                else
                {
                    $preprocess->run_fusion_mpatch_build($bugfix_request_id);
                }
            }
            elsif ($gen_or_port eq "O")
            {
                $preprocess->run_fusion_oneoff_build($bugfix_request_id);
            }
            my $skip_step_fh = FileHandle->new("$skip_step_ts", 'w');
            $skip_step_fh->print(time);
            $skip_step_fh->close;

            if (defined $preprocess->{empty_payload})
            {
              $log_fh->print_header("Denying due to empty payload");
              $log_fh->print("Denying patch due to empty payload\n");
                if ($aru_obj->{language_id} == ARU::Const::language_US)
                {
              ARUDB::exec_sp('pbuild.update_empty_payload',
                              $preprocess->{base_bug},$aru_obj->{aru},
                              ARU::Const::patch_denied_empty_payload,
                              ARU::Const::apf2_userid,
                              "The transaction ".
                              "$preprocess->{transaction_name} ".
                              "does not impact any shippable patch content",
                              ARU::Const::checkin_on_hold,
                              $aru_obj->{release_id});
                 $self->update_on_hold_bug_status($preprocess->{base_bug});
                }
                else
                {
                    ARUDB::exec_sp('apf_queue.update_aru', $bugfix_request_id,
                                   ARU::Const::patch_denied_empty_payload,
                                   "The patch does not have any shippable ".
                                   "content", ARU::Const::apf2_userid);
                }
              return;
            }
        }
        elsif($preprocess->is_DST_patch())
        {
          $generic_port->dst_build();
          $self->{DST} = 1;
        }
        else
        {
            my $java_bld_status = $generic_port->java_build();

            #
            # We should not run build twice if the product's build
            # instructions build its entire repository.
            #
            if (! $self->is_bi_product($aru_obj->{product_id})
                    && $java_bld_status != 1)
            {
                $generic_port->plb_build();
            }
        }

          #
          # fix for bug 13417939
          # enable standalone patches for soa
          # set a flag is_saoui=true if
          # top_level_component is mapped with
          # label_dependency as SAOUI/SA/OUI
          #


      $self->{is_sa} = $generic_port->{is_sa};
      $self->{is_saoui} = $generic_port->{is_saoui};
      $self->{is_oui} = $generic_port->{is_oui};
        $self->{is_ocom} = $generic_port->{is_ocom};
      $self->{static_jar_str} = $generic_port->{static_jar_str};
        if (defined $generic_port->{group_id} &&
            $generic_port->{group_id} ne "")
        {
            $self->{group_id} = $generic_port->{group_id};
        }

        $self->{aru_obj} = $preprocess->{aru_obj} if (! $self->{aru_obj});
        if ($aru_obj->{release_id} =~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/ &&
            $patch_type != ARU::Const::ptype_merged &&
            $bundle_type !~ /merged/i)
        {
            $preprocess->{wkr} = $self->_run_fusion_portbuild(
                                          $preprocess,$params)
                        if($aru_obj->{language_id} == ARU::Const::language_US);
            if ($self->{switched_aru_platform}) {
              $aru_obj = $self->{aru_obj};
              $params->{aru_no} = $aru_obj->{aru};
            }
            $log_fh->print("DEBUG: FUSION ARU PSE : ".
                           "$preprocess->{aru_obj}->{ARU_PSE_BUG},".
                           "$aru_obj->{ARU_PSE_BUG} \n");
            #
            # Generate bugfix relationships
            # Skip seeding bugfix relationships for NLS/platform patches as
            # these are at the checkin level, these need to be seeded only once
            # during base platform US patch build
            #
            if ($aru_obj->{language_id} == ARU::Const::language_US &&
                ($aru_obj->{platform_id} == ARU::Const::platform_generic ||
                $aru_obj->{platform_id} == ARU::Const::platform_linux64_amd))
            {
                # Verify if seeding is done already
                my ($txn_id, $basetxn_dos_seeded);
                ($txn_id) =
                    ARUDB::exec_sf('aru.aru_transaction.get_transaction_id',
                                   $aru_obj->{bugfix_id}, $aru_obj->{aru},
                                   ['boolean', 0]);
                ($basetxn_dos_seeded) =
                ARUDB::exec_sf('aru.aru_transaction.get_attribute_value',
                               $txn_id, ARU::Const::trans_attrib_basetxn_seeded,
                               ['boolean', 0]) if ($txn_id);
                if ($basetxn_dos_seeded eq "YES")
                {
                    $log_fh->print("\nBugfix relationship seeding is already ".
                                   "done for current transaction.\n");
                }
                else
                {
                    $preprocess->gen_bugfix_relationships();
                    ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                                   $txn_id,
                                   ARU::Const::trans_attrib_basetxn_seeded,
                                   'YES') if ($txn_id);
                }

                $preprocess->is_circular_dependency();
                $preprocess->process_coreqs();

                $log_fh->print("Checking for patches that are replaced ".
                               "based on current patch..\n");
                my ($repl_update_reqd) = ARUDB::exec_sf_boolean(
                    "aru.apf_patch_supersedure.is_replace_patch_update_reqd",
                    $preprocess->{base_bug}, $aru_obj->{release_id});
                if ($repl_update_reqd)
                {
                    $log_fh->print("Updating patches that are replaced ".
                                   "based on current patch..\n");
                    ARUDB::exec_sp(
                       "aru.apf_patch_supersedure.update_replacement_bugfix",
                       $aru_obj->{bugfix_id}, ARU::Const::apf2_userid);
                }
                else
                {
                     $log_fh->print("There are no patches replaced based on ".
                                    "current patch.\n");
                }

                $log_fh->print("Checking for patches that may have skipped ".
                               "based on current patch..\n");
                my ($skip_update_reqd) = ARUDB::exec_sf_boolean(
                    "aru.apf_patch_supersedure.is_skip_patch_update_reqd",
                            $preprocess->{base_bug},
                            $aru_obj->{release_id});
                if ($skip_update_reqd)
                {
                    $log_fh->print("Updating patches that skipped based on ".
                                   "current patch..\n");
                ARUDB::exec_sp("aru.apf_patch_supersedure.update_skipped_patch",
                               $aru_obj->{bugfix_id},
                               ARU::Const::apf2_userid);
                }
                else
                {
                    $log_fh->print("There are no patches that are skipped ".
                                   "based on current patch.\n");
                }

                # Check if the patch needs to be marked as replaced
                my ($repl_reqd) = ARUDB::exec_sf_boolean(
                       "aru.apf_patch_supersedure.is_patch_needs_replacement",
                       $aru_obj->{bugfix_id});
                if ($repl_reqd)
                {
                    ARUDB::exec_sp(
                        "aru.apf_patch_supersedure.mark_patch_for_replacement",
                        $aru_obj->{bugfix_id}, ARU::Const::apf2_userid);
                }
            }

            #
            # Run one-off buster logic
            #
            $preprocess->gen_oneoff_buster();

            #
            # Generate Fusion AutoPatch Metadata and run AutoPatch
            #
            $params->{action_desc} = 'Generate AutoPatch Driver Metadata';
            $log_fh->print_header($params->{action_desc});
            $log_fh->print("DEBUG: FUSION ARU PSE : ".
                           "$preprocess->{aru_obj}->{ARU_PSE_BUG},".
                           "$aru_obj->{ARU_PSE_BUG}, ".
                           "$preprocess->{release_name} \n");
            $preprocess->gen_autopatch_driver($preprocess->{ade_view_root},
                                              $bugfix_request_id, $work_area);

            #
            # Generate Fusion Upperwrapper Metadata and run
            # adUpdateMetadata.pl to update patch upperwrapper file
            #
            $params->{action_desc} = 'Generate Upperwrapper Metadata';
            $log_fh->print_header($params->{action_desc});
            $log_fh->print("DEBUG: FUSION ARU PSE : ".
                           "$preprocess->{aru_obj}->{ARU_PSE_BUG},".
                           "$aru_obj->{ARU_PSE_BUG} \n");
            $preprocess->update_upperwrapper_file($preprocess->{ade_view_root},
                                              $bugfix_request_id, $work_area);
        }
    }

    $params->{action_desc} = 'Generate README';
    if ($aru_obj->{release_id} =~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        $log_fh->print_header($params->{action_desc});
    }
    else
    {
        $log_fh->print_header($params->{action_desc})
        unless($self->skip_header($params));
    }


    #
    # fix for bug 13417939
    # enable standalone patches for soa
    # set a flag is_saoui=true if
    # top_level_component is mapped with
    # label_dependency as SAOUI/SA/OUI
    #

    $preprocess->{is_sa}    = $self->{is_sa};
    $preprocess->{is_saoui} = $self->{is_saoui};
    $preprocess->{is_oui}   = $self->{is_oui};
    $preprocess->{is_ocom}  = $self->{is_ocom};
    $preprocess->{static_jar_str} = $self->{static_jar_str};

    $self->{emcc_enabled} = APF::PBuild::Util::is_emcc_installtest($aru_obj);
    $preprocess->{emcc_enabled} = $self->{emcc_enabled};

    my ($product_family, $parent_prod_id) =
                   $preprocess->get_product_family
                           ($aru_obj->{platform_id},
                            $aru_obj->{product_id},
                            $aru_obj->{release_id});
    $preprocess->{product_family} = $product_family;

    #
    # pass em_product_id to preprocess
    # for em ps2 agent a different readme has to be used
    #
    $preprocess->{em_product_id} = $em_product_id;

    $log_fh->print("DEBUG: README ARU PSE : ".
                   "$preprocess->{aru_obj}->{ARU_PSE_BUG},".
                   "$aru_obj->{ARU_PSE_BUG} \n");

    if ($aru_obj->{release_id} =~
             /^${\ARU::Const::applications_fusion_rel_exp}\d+$/ &&
        ($patch_type == ARU::Const::ptype_merged ||
         $bundle_type =~ /merged/i))
    {
        $preprocess->_gen_fusion_mpatch_readme();
    }
    else
    {
        $preprocess->_generate_readme_files();
    }

    $aru_obj->{transaction_details} = $preprocess->{transaction_details};

    my $backport_sql = lc($aru_obj->{transaction_details}->{BACKPORT_SQL})
                                            || "";

    $log_fh->print(" Transaction property BACKPORT_SQL set to:" .
                   " $backport_sql for transaction $transaction_name\n");
    my $base_label = $preprocess->{base_label_name} || "";
    $log_fh->print(" Base label set to: $base_label");

    my $start_mode = "";
    my $sql_aref;
    $self->{backport_sql_enabled}  = 0;

    #
    # If ADE transaction property BACKPORT_SQL is set to true in the
    # transaction, call SQL automation to create apply and rollback scripts.
    #
    my ($datapatch, $pre12_datapatch) =
        $preprocess->is_datapatch({release=>$aru_obj->{release},
                                   request_id=>$self->{request_id}
                                  });

    $self->{all_upg_dwng_files}  = 0;
    if($product_family=~ /orcl_pf/i) {

        my $backport_bug_num = $self->{transaction_details}->{BACKPORT_BUG_NUM}
                                             || "";
        my $base_bug = $self->{transaction_details}->{BUG_NUM};

        if ((! defined $aru_obj->{utility_version}) ||
             $aru_obj->{utility_version} eq "")
        {
            $aru_obj->{utility_version} = $preprocess->{utility_version};
        }
        $aru_obj->{patch_uid} = $params->{aru_no};
        my $sql_auto = APF::PBuild::STAPFSqlAutomation->new($transaction_name,
                                                            $aru_obj,
                                                            $base_label,
                                                            $work_area,
                                                            $log_fh,
                                                            $pse);
        $sql_auto->{request_id} = $self->{request_id};

        if($preprocess->{base_label_name})
        {
         $log_fh->print("Passing following info  to SQLAuto \n");
         $log_fh->print("$preprocess->{base_label_name} , $preprocess->{psu_base_label_name}, $preprocess->{base_label_id} ,".
                        "$preprocess->{label_name}, $preprocess->{label_id} , $preprocess->{psu_label_id}, $preprocess->{psu_label_name} \n");

         $sql_auto->{base_label_name} = $preprocess->{base_label_name};
         $sql_auto->{base_label} = $preprocess->{base_label_name};
         $sql_auto->{psu_base_label_name} = $preprocess->{psu_base_label_name};
         $sql_auto->{psu_base_label_id} = $preprocess->{psu_base_label_id};
         $sql_auto->{base_label_id} = $preprocess->{base_label_id};
         $sql_auto->{label_name} = $preprocess->{label_name};
         $sql_auto->{label_id} = $preprocess->{label_id};
         $sql_auto->{psu_label_id} = $preprocess->{psu_label_id};
         $sql_auto->{psu_label_name} = $preprocess->{psu_label_name};
        }

        $params->{action_desc} = 'Validating SQL metadata';

         my $skip_header = $self->skip_header($params);

         if ($skip_header == 1)
         {
           $sql_auto->{skip_header} = 1;
         }
         else
         {
          $sql_auto->{skip_header} = 0;
          $log_fh->print_header($params->{action_desc});
         }


        if($datapatch && $pre12_datapatch)
        {
         my $ade_obj = new SrcCtl::ADE({'filehandle' => $log_fh});
         $ade_obj->get_transaction_metadata($transaction_name);

         my $apply_files =
             $ade_obj->{transaction}->{BACKPORT_SQL_APPLY_FILES} || "";

         if (($backport_sql eq "") && ($apply_files eq ""))
         {
           $apply_files = $sql_auto->_set_ade_sql_properties(
                                       $transaction_name, $ade);
           $ade_obj->get_transaction_metadata($transaction_name);
         }
        }

        my $status = APF::Config::sql_auto_metadata_validation_failure;
        my $validation_enabled =
                   APF::Config::sql_auto_metadata_validation_enabled;
        if($validation_enabled)
        {
         $status = $sql_auto->validate_sql_txn();
        }
        else
        {
         $status = APF::Config::sql_auto_metadata_validation_success;
        }

        if (defined $backport_sql && uc($backport_sql) eq "TRUE" &&
            $status == APF::Config::sql_auto_metadata_validation_no_sql)
        {
            die (" No SQLs in the transaction but the BACKPORT_SQL is ".
                 " set to TRUE \n");
        }

        if($status == APF::Config::sql_auto_metadata_validation_success &&
           $datapatch)
        {
         $params->{action_desc} = 'Create SQL apply and rollback scrpits';
         $log_fh->print_header($params->{action_desc})
             unless($skip_header);

         ($start_mode, $sql_aref) = $sql_auto->gen_scripts();
        }
        elsif($status ==
              APF::Config::sql_auto_metadata_validation_all_upg_dowg)
        {
         $self->{all_upg_dwng_files}  = 1;
         ARUDB::exec_sp("aru.aru_bugfix_attribute.set_bugfix_attribute",
                        $aru_obj->{bugfix_id},
                        ARU::Const::all_upg_dwng_files,'YES');
        }
        elsif($status ==
              APF::Config::sql_auto_metadata_validation_no_sql)
        {
         $log_fh->print("Setting no_sql_ship to 1\n");
         $self->{no_sql_ship}  = 1;
         ARUDB::exec_sp("aru.aru_bugfix_attribute.set_bugfix_attribute",
                        $aru_obj->{bugfix_id},
                        ARU::Const::no_sql_ship,'YES');
        }

        $self->{backport_sql_enabled}  = 1 if ($datapatch && !$pre12_datapatch);
        $self->{oraver_comp_ver} = $sql_auto->{labelCompositeVer};
    }

    $params->{action_desc} = 'Generate Template File';
    if ($aru_obj->{release_id} =~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        $log_fh->print_header($params->{action_desc});
    }
    else
    {
        $log_fh->print_header($params->{action_desc})
        unless($self->skip_header($params));
    }

    my $fixedbugs = $preprocess->{fixedbugs};

    #
    # ! HACK ! HACK ! HACK !
    #  Bug  14516426 - populate fixedbugs for HCM bundle patch 14107782
    #
    if ($aru_obj->{language_id} != ARU::Const::language_US &&
        $aru_obj->{bug} == 14107782)
    {
        $fixedbugs = join(' ',
                          ARUDB::single_column_query('GET_ALL_FIXED_BASE_BUGS',
                                                     $aru_obj->{bug},
                                                     $aru_obj->{release_id}));
        $preprocess->{fixedbugs} = $fixedbugs;
    }

    my $tmpl_obj =
        APF::PBuild::TemplateGen->new($aru_obj, $work_area,$aru_obj->{aru},
                                      $blr,$log_fh);

    $tmpl_obj->{ade_view_root} = $preprocess->{ade_view_root};
    $tmpl_obj->{ade_view_name} = $preprocess->{ade_view_name};
    $tmpl_obj->{is_sa} = $self->{is_sa};
    $tmpl_obj->{is_saoui} = $self->{is_saoui};
    $tmpl_obj->{is_oui} = $self->{is_oui};
    $tmpl_obj->{emcc_enabled} = $self->{emcc_enabled};
    $tmpl_obj->{static_jar_str} = $self->{static_jar_str};
    $tmpl_obj->{em12c_product_id} = $self->{em12c_product_id};
    $tmpl_obj->{all_upg_dwng_files} = $self->{all_upg_dwng_files};
    $tmpl_obj->{no_sql_ship} = $self->{no_sql_ship};
    $tmpl_obj->{oraver_comp_ver} = $self->{oraver_comp_ver};
    #
    # enable em ps2, bug 17217952
    # preprocess generate_readme has already determined
    # em release_id and release_name, pass it to templategen
    #
    $tmpl_obj->{em_release_id} = $preprocess->{release_id};
    $tmpl_obj->{em_release_name} = $preprocess->{release_name};
    $tmpl_obj->{is_oms_rolling}='true' if($preprocess->{oms_rolling} eq 'YES');
    $tmpl_obj->{is_oms_rolling}='false' if($preprocess->{oms_rolling} eq 'NO');
    $preprocess->{db_start_mode} = "normal";
    if ($start_mode ne "") {

        $log_fh->print("SQL start mode: $start_mode\n");
        $tmpl_obj->{start_mode} = $start_mode;
        $tmpl_obj->{sql_h} = $sql_aref;
        $preprocess->{db_start_mode} = lc($start_mode);
    }

    if ($self->{backport_sql_enabled} &&
        ($start_mode && ($start_mode =~ /upgrade/i))) {
      $log_fh->print("Re-generating README with starting db in $start_mode mode\n");
      $preprocess->_generate_readme_files();
    }

    $log_fh->print("DEBUG: TEMPLATEGEN: ARU PSE : ".
                   "$preprocess->{aru_obj}->{ARU_PSE_BUG},".
                   "$aru_obj->{ARU_PSE_BUG} \n");

    #
    # Save the release_id.
    #
    my $saved_release_id = $aru_obj->{release_id};
    my $is_hybrid = $tmpl_obj->create_template($aru_obj->{aru},
                                               $ade->{transaction},
                                               $self->{action},
                                               $self->{output_dir},
                                               $fixedbugs, $gen_or_port);
    $preprocess->{em_metadata_xml} = $tmpl_obj->{em_metadata_xml};
    $self->{em_metadata_xml} = $tmpl_obj->{em_metadata_xml};

    $log_fh->print("Calling filter_dup_artifacts..\n");
    $tmpl_obj->filter_dup_artifacts();

    #
    # Restore the release_id. It has been manipulated in TemplateGen.
    #
    $self->{aru_obj}->{release_id} = $saved_release_id;
    $aru_obj->{release_id} = $saved_release_id;

    $log_fh->print("EMCC enabled1:\t$self->{emcc_enabled}," .
                   "sql_files:\t$tmpl_obj->{sql_files}\n");

    if ((!$self->{backport_sql_enabled}) &&
                ($tmpl_obj->{sql_files} &&
                    ($tmpl_obj->{product_family} =~ /orcl_pf/i))) {
        $params->{action_desc} = 'Create PostInstall SQL';
        $log_fh->print_header($params->{action_desc})
            unless($self->skip_header($params));
        $log_fh->print("Generating postinstall.sql\n");
        my $sql_auto =
            APF::PBuild::STAPFSqlAutomation->new(
                       $transaction_name,
                       $aru_obj,
                       $preprocess->{base_label_name},
                       $work_area,
                       $log_fh, $pse);
        $sql_auto->{request_id} = $self->{request_id};

        if($preprocess->{base_label_name})
        {
         $log_fh->print("Passing following info  to SQLAuto POSTINSTALL \n");
         $log_fh->print("$preprocess->{base_label_name} , $preprocess->{psu_base_label_name}, $preprocess->{base_label_id} ,".
                        "$preprocess->{label_name}, $preprocess->{label_id} , $preprocess->{psu_label_id}, $preprocess->{psu_label_name} \n");

         $sql_auto->{base_label_name} = $preprocess->{base_label_name};
         $sql_auto->{base_label} = $preprocess->{base_label_name};
         $sql_auto->{psu_base_label_name} = $preprocess->{psu_base_label_name};
         $sql_auto->{psu_base_label_id} = $preprocess->{psu_base_label_id};
         $sql_auto->{base_label_id} = $preprocess->{base_label_id};
         $sql_auto->{label_name} = $preprocess->{label_name};
         $sql_auto->{label_id} = $preprocess->{label_id};
         $sql_auto->{psu_label_id} = $preprocess->{psu_label_id};
         $sql_auto->{psu_label_name} = $preprocess->{psu_label_name};
        }
        my ($tstart_mode, $spec_aref) =
              $sql_auto->gen_postinstall_sql($tmpl_obj->{sql_copy_files});
        $sql_auto->{postinstall_sql_content} ||= 0;

        if (!$sql_auto->{postinstall_sql_content}) {
          # Regenerate the template file
          $tmpl_obj->{generate_postinstall_sql} = 0;
          $log_fh->print("generate_postinstall_sql:\t" .
                         $tmpl_obj->{generate_postinstall_sql} . "\n");
          $log_fh->print("Re-creating the template without postinstall.sql\n");

          $tmpl_obj->create_template($aru_obj->{aru},
                                     $ade->{transaction},
                                     $self->{action},
                                     $self->{output_dir},
                                     $fixedbugs, $gen_or_port);

          $log_fh->print("Re-generating README without postinstall.sql\n");
          $preprocess->{has_postinstall_sql_file} = "NO";

          $preprocess->_generate_readme_files();

        } elsif (($sql_auto->{sql_exception_list}) ||
                 ($sql_auto->{sql_notincluded_list})) {
          # Update bug with missing files in sqlphases.xml
          $log_fh->print("Updating bug with postinstall exceptions\n");
          $sql_auto->_update_bug_postinstall_exceptions(
                                        $pse, $transaction_name)
              unless($self->skip_header($params));
        }

        if (scalar(@$spec_aref) != 0) {

          $tmpl_obj->{sql_a} = $spec_aref;
          $tmpl_obj->create_template($aru_obj->{aru},
                                     $ade->{transaction},
                                     $self->{action},
                                     $self->{output_dir},
                                     $fixedbugs, $gen_or_port);
        }
    }

    $self->{psu} = $tmpl_obj->{psu};
    if ($self->{action} eq "request"||
        ($self->{action} eq "preprocess" &&
         ($aru_obj->{language_id} != ARU::Const::language_US)))
    {
        $aru_obj->get_details;
        my $requires_porting ='';
        $requires_porting = $preprocess->check_requires_porting
            if ($aru_obj->{release_id} !~
                     /^${\ARU::Const::applications_fusion_rel_exp}\d+$/);

        if ($preprocess->{platform_id} ne ARU::Const::platform_generic_bugdb
            and $requires_porting eq 'Y'
            and $aru_obj->{language_id} == ARU::Const::language_US
            and (not defined $self->{DST})
            and $aru_obj->{release_id} !~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
        {
            $log_fh->print_header("Port Platform Specific Files")
                unless($self->skip_header($params));
            $params->{action_desc} = 'Port Platform Specific Files';

            if (($self->is_bi_product($aru_obj->{product_id})) &&
               (($aru_obj->{platform_id} == ARU::Const::ms_windows_nt_server) or
                ($aru_obj->{platform_id} == ARU::Const::platform_windows64)))
            {
                my $farm_job =
                    APF::PBuild::FarmJob->new(
                             {bugfix_req_id    => $aru_obj->{aru},
                              request_id       => $params->{request_id},
                              log_fh           => $log_fh,
                              bug              => $pse,
                              view_name        => $preprocess->{ade_view_name},
                              transaction_name => $transaction_name,
                             });

                $farm_job->submit_farm_build();
                return;
            }
            else
            {
                my $wkr = APF::PBuild::PortBuild->new($aru_obj, $work_area,
                                                      $log_fh, $is_hybrid,
                                                      $pse, $blr,
                                                      $basebug, $ver,
                                                      $transaction_name);
                $wkr->{isd_request_id} = $self->{request_id};
                $wkr->{throttle_req_type} =
                    ARU::Const::throttle_build_type;

                if ($wkr->is_build_required())
                {
                    $wkr->{request_id}  = $self->{request_id};
                    $wkr->{preprocess}  = $self->{preprocess};
                    $wkr->{user_id}     = $self->{params}->{user_id};
                    $wkr->{config_file} = $self->{config_file};

                    #
                    # Checked for branched files
                    # 0 = There area no Branched File(s)
                    # 1 = Branched File(s) transaction exists
                    # 2 = Created Merged transaction and submitted
                    #     Regression test_snowball_dep_chkins
                    #
                    my $return_code = $wkr->preProcess($aru_obj->{aru},0);
                    return
                        if ($return_code == PB::Config::check_farm_job_status);

                    $wkr->port_build($aru_obj->{aru},0,$return_code,undef);

                    #
                    # If Hybrid objects need to be built
                    #
                    if ($is_hybrid) {
                        $return_code = $wkr->preProcess($aru_obj->{aru},1);
                        return
                        if ($return_code == PB::Config::check_farm_job_status);

                        $wkr->port_build($aru_obj->{aru},1,$return_code,undef);
                    }
                    $wkr->free_throttle_resource(
                                             $wkr->{isd_request_id},
                                             ISD::Const::isd_request_stat_succ);

                    #
                    # Checkin whether the EM patch has perl files
                    # Ref bug:10085011
                    #
                    $wkr->is_generic_patch()
                        unless ($return_code);
                }
            }
        }

        #
        # calling PostProcessing action
        #
        $params->{aru_dir}  = $self->{aru_dir};
        $params->{aru_log}  = $self->{aru_log};
        $params->{ade_view_root}   = $preprocess->{ade_view_root};
        $params->{ade_view_name}   = $preprocess->{ade_view_name};
        $params->{utility_version} = $preprocess->{utility_version};
        $params->{blr}      = $preprocess->{blr};
        $params->{is_sa}    = $self->{is_sa};
        $params->{is_saoui} = $self->{is_saoui};
        $params->{is_oui}   = $self->{is_oui};
        $params->{static_jar_str} = $self->{static_jar_str};
        $params->{fixed_bugs} = $fixedbugs;
        $params->{fa_prodfam_label} = $preprocess->{fa_prodfam_label};
        #
        # For em12c plugins, there are multiple releases for each plugin
        # based on if patch is for oms or agent or discovery
        # we need to set a tag to patch if discovery
        # apf bug 16276795
        #
        $params->{plugin_type} = $preprocess->{plugin_type};
        $params->{is_discover} = $preprocess->{is_discover};
        #
        # for em ps2 agent, bug 17358015
        # second template should not be used for packaging
        # it should be used only for oms server patches
        #
        $params->{em_product_id} = $preprocess->{em_product_id};
        $params->{em_release_id} = $preprocess->{release_id};
        $params->{em_release_name} = $preprocess->{release_name};
        $params->{em_metadata_xml} = $preprocess->{em_metadata_xml};

        # fix for 13241776
        # set oms_rolling tag for
        # em rolling patches

        if ($preprocess->{sql_files} ne "YES" &&
           ($aru_obj->{product_id} == ARU::Const::product_smp_pf ||
            $aru_obj->{product_id} == ARU::Const::product_emgrid ))
        {
           $params->{oms_rolling}=1;
        }
        else
        {
           $params->{oms_rolling}=0;
        }

        $params->{oms_rolling} = 1
                 if($preprocess->{oms_rolling} eq "YES");
        $params->{oms_rolling} = 0
                 if($preprocess->{oms_rolling} eq "NO");

        if ($tmpl_obj->{sql_files} == 1)
        {
           $params->{sql_files} = 1;
        }
        else
        {
           $params->{sql_files} = 0;
        }

        $self->_postprocess($params);

    }
    $self->{preprocess} = undef;
}

sub _build
{
    my ($self, $params) = @_;

    my $bugfix_request_id = $self->{bugfix_request_id} = $params->{aru_no};
    my $request_id        = $params->{request_id};
    my $preprocess      = APF::PBuild::PreProcess->new($params);
    $self->{preprocess} = $preprocess;
    my $gen_or_port     = $preprocess->get_gen_port($params->{bug});
    $self->{gen_port}   = $gen_or_port;
    my $log_fh          = $self->{aru_log};

    $preprocess->preprocessMerge($bugfix_request_id);

    my $work_area = $preprocess->{work_area};
    my $bug       = $preprocess->{bug};
    my $aru_obj   = $preprocess->{aru_obj};
    my $base_bug  = $preprocess->{base_bug};
    my $user_id   = $preprocess->{user_id};
    
    $self->{workarea} = $work_area;
    $self->{log_fh}   = $log_fh;
    $self->{aru_obj}  = $aru_obj;
    $self->{base_bug} = $base_bug;

    my $base =  APF::PBuild::Base->new(work_area  => $work_area,
                                       request_id => $request_id,
                                       pse    => $params->{psu_aru},
                                       aru_obj => $aru_obj,
                                       log_fh => $self->{aru_log});

    die("Merge Error: Pinging host timed out.")
      if ($base->_get_ssh_object($preprocess->{label_id}, ISD::Const::st_mlr) != 1);
    #
    # Check whether the request is for describe mode
    #
    my ($aru_comment) =
        ARUDB::single_row_query('GET_ARU_REQUEST_COMMENT',
                                $aru_obj->{aru});

    my @aru_comments  = split(/\|/, $aru_comment);
    my @pbuild_params = split(':',$aru_comments[1]);

    $self->{$pbuild_params[0]}     = $pbuild_params[1];
    $self->{lc($pbuild_params[0])} = lc($pbuild_params[1]);

    my ($request_param_value) =
        ARUDB::single_row_query('GET_ST_APF_BUILD',
                                $self->{req_id});

    foreach my $i (split('!',$request_param_value))
    {
        my ($key, $value) = split(':',$i);
        $self->{$key} = $value;
        $self->{lc($key)} = lc($value);
    }

    my ($group_id);
    eval
    {
        ($group_id) = ARUDB::single_row_query("GET_APF_REQUEST_GROUP",
                                              $request_id);
    };

    $self->{group_id} = $group_id
        if (defined $group_id && $group_id ne "");


    #
    # Calling GIT backport processing routine.
    #
    eval {
         $self->initialize_git_src_ctrl_type($bug);
    };

    if( $self->{src_ctrl_type} =~ /git/i )
    {
        #Fetch the value of sqlok param if set
        my ($non_binary_ok, $reason);


        $non_binary_ok = $preprocess->{SQLOK};
        my $farmdiffok = $preprocess->{FARMDIFFOK};

        
        $log_fh->print("This is a GIT Source control type backport\n");
        $log_fh->print("Calling the python to process the GIT backport\n");
        $log_fh->print("Req ID: $self->{request_id} \n");

        $log_fh->print("Non Binary Files validation in the backport branch: $non_binary_ok .\n");


        #Check for farmdiffok. If it is set, ignore farm diffs 
        #and call 'commit branch' for backport closure.

        if (defined $farmdiffok && $farmdiffok == 1)
        {
            my $url_host_port = PB::Config::url_host_port;
            my $port;
            ($url_host_port, $port) = split(':',$url_host_port)
                                     if (ConfigLoader::runtime("production"));
            #Get worker Host
            my ($worker_host) = ARUDB::single_row_query("GET_WORKER_HOST",
                                                     $self->{backport_bug});

            $worker_host = (split ',', $worker_host)[-1];
            $worker_host = (split ':', $worker_host)[0];

            $params->{action_desc} = 'Ignore Farm diffs';
            $log_fh->print_header($params->{action_desc});
            $log_fh->print("This is a GIT Source control type backport\n");
            $log_fh->print("Ignoring the farm diffs and proceeding with branch commit " .
                            " and push followed by and backport closure\n");
            my $func_name = 'ignore_farm_diffs';
            eval
            {
                $preprocess->{system}->do_cmd(APF::Config::python_home . APF::Config::merge_git_wrapper .
                                              " $params->{aru_no} $bug $func_name $work_area " .
                                              " $base->{wkr_host} --non_bin_ok=$non_binary_ok ");

            };
            if ($@)
            {
                #$preprocess->free_throttle_resource($request_id,
                #                #                                    ISD::Const::isd_request_stat_succ);

                $log_fh->print("GIT Processing caused some error. Check the logs for details\! \n");
                $log_fh->print("Error during GIT processing in python module: " . $@ . "\n");
                die($@)
            }
 
            $log_fh->print("Farm diffs Ignored");            
        }
        else
        {    

            $params->{action_desc} = 'Create, Build and Test GIT Branch';

            #Calling the ARUDB_ConnectionString.py to get the creds
            $log_fh->print_header($params->{action_desc});
            my $func_name = 'verify_handover_backport';
        
            eval
            {
                $preprocess->{system}->do_cmd(APF::Config::python_home . APF::Config::merge_git_wrapper . 
                                              " $params->{aru_no} $bug $func_name $work_area " .
                                              " $base->{wkr_host} --non_bin_ok=$non_binary_ok ");

            };
            if ($@) 
            {
                #$preprocess->free_throttle_resource($request_id,
                #                                    ISD::Const::isd_request_stat_succ);

                $log_fh->print("GIT Processing caused some error. Check the logs for details\! \n");
                $log_fh->print("Error during GIT processing in python module: " . $@ . "\n");
                die($@)
            }

            $log_fh->print("GIT Processing Ended");

            #
            #The resource will be freed post backport completion at 'Commit Branch' phase due to OIM farm exception.
            #
        
            #$preprocess->free_throttle_resource($request_id,
            #                          ISD::Const::isd_request_stat_succ);
        }

    }
    else
    {
        my ($destroytrans, $requested_by);
        ($destroytrans) = ARUDB::exec_sf('apf_build_request.getDestroyTrans',
                                         $bug, \$requested_by);
 
        $params->{action_desc} = ($destroytrans == 0) ? 'Create Transaction' :
                                 'Destroy Transaction';

        $log_fh->print_header($params->{action_desc})
            unless($self->skip_header($params));

        my $merge =  APF::PBuild::Merge->new($aru_obj, $request_id,
                                         $work_area, $log_fh);
        $merge->{request_id} = $merge->{isd_request_id} = $request_id;
        $merge->{user_id} = $user_id;

        my $share_trans = 0;
        my $ret = $merge->check_trans_exists($base_bug, $bug,
                  $request_id, $destroytrans);
 
        if ($destroytrans == 1)
        {
            eval
            {
                $merge->destroyTransaction($requested_by);
                $params->{action_desc} = 'Create Transaction';
 
                $log_fh->print_header($params->{action_desc})
                    unless($self->skip_header($params));
                $ret = APF::Const::sb_txn_not_found;
            };
 
            if ($@)
            {
                die("Unable to destroy transaction, plese review the logs - $@");
            }
        }

        #
        # $ret == sb_txn_not_found   => No transaction found
        # $ret == sb_txn_open        => Transaction found in open status,
        #                               No regressions are running.
        # $ret == sb_txn_in_reg      => Regressions are running.
        # $ret == sb_txn_handed_over => Handed over transaction
        # $ret == sb_txn_abort       => Abort transaction
        # $ret == sb_txn_commit      => Commit transaction
        # $ret == sb_txn_do_nothing  => Do nothing
        #
        if ($ret == APF::Const::sb_txn_handed_over)
        {
            $share_trans = 1;
            $ret = APF::Const::sb_txn_not_found;
        }

        if ($ret == APF::Const::sb_txn_not_found ||
            $ret == APF::Const::sb_txn_open)
        {
            $merge->Build($base_bug, $bug, $share_trans)
               if ($ret == APF::Const::sb_txn_not_found);

            $merge->preBuildSteps();

            $params->{action_desc} = 'Compile Transaction';
            $log_fh->print_header($params->{action_desc});
            my $runRegress = $merge->buildFiles();

        #
        # Some products like OUD should run unit test
        # before submitting to farm. Bug-30410505
        #
            $merge->postBuildSteps();

            if( $merge->{product_family} eq "orcl_pf" and
                $merge->is_invalid_obj_regression_required($runRegress, $bug) )
            {
              $log_fh->print("Invalid object regresssion required \n");
              $runRegress = 1;
              if (ConfigLoader::runtime("development","demo","sprint"))
              {
                $merge->set_BG_alt_properties();
              }
            }

            $merge->free_throttle_resource($merge->{request_id},
                                       ISD::Const::isd_request_stat_succ)
            if (defined $merge->{worker_throttling} &&
                $merge->{worker_throttling} != 1);

            if ($merge->skip_farm())
            {
                $log_fh->print("\n\nFarm submission has been disabled, " .
                               "skipping....\n\n");
                $runRegress = 0;
            }

            my $src_txn = $merge->{source_trans};
            my $txn     = $merge->{transaction};

        #
        # Skip Farm regression if it Diagnostic
        #
            if ($runRegress && (! $merge->{diagnostic}))
            {
                $merge->free_throttle_resource($merge->{request_id},
                                           ISD::Const::isd_request_stat_succ)
                if (defined $merge->{worker_throttling} &&
                    $merge->{worker_throttling} == 1);

                $params->{action_desc} = 'Test Transaction';
                $log_fh->print_header($params->{action_desc});

                $merge->submitFarmRegress();
            }
            else
            {
                my $act_desc = ($gen_or_port eq 'I' || $gen_or_port eq 'Z') ?
                               "Submit MergeReq" :
                               "Commit Transaction";

                $params->{action_desc} = $act_desc;
                $log_fh->print_header($params->{action_desc});

                $merge->postProcess($merge->{transaction},
                                    $bug, $base_bug,
                                    $merge->{errmsg});
            }
        }
        elsif ($ret == APF::Const::sb_txn_abort ||
               $ret == APF::Const::sb_txn_commit)
        {
            $merge->{errmsg} = "Error occurred during processing of backport."
                if ($ret == APF::Const::sb_txn_abort);

            $params->{action_desc} = 'Commit Transaction';
            $log_fh->print_header($params->{action_desc});

            $merge->postProcess($merge->{transaction},
                                $bug, $base_bug,
                                $merge->{errmsg});
        }
        $merge->free_throttle_resource($merge->{request_id},
                                   ISD::Const::isd_request_stat_succ);
    }
    
    $self->{preprocess} = undef;
}

#
# For Bundle Patch Post script transcations
#
sub _bpr_post_script_txn
{
    my ($self,$params) = @_;
    $self->{log_fh} = $params->{log_fh};
    my $bugfix_request_id   = $self->{bugfix_request_id} = $params->{aru_no};
    my $bundlepatch         = APF::PBuild::BundlePatch->new($params);
    my $preprocess          = APF::PBuild::PreProcess->new($params);
    $bundlepatch->{preprocess} = $preprocess;
    $bundlepatch->{bpr}     = $params->{bug};
    $bundlepatch->{bpr_txn} = $params->{txn};
    $bundlepatch->{bpr_third_party} = $params->{third_party};
    #
    # Process the FDE transaction along with the third party files
    #
    $bundlepatch->process_post_script_txn($bugfix_request_id);
}


#
# For EM Install Test farm job tracking
#
sub _check_farm_em_job_status
{
    my ($self, $params) = @_;

    $self->{force_retry} = 1;
    my $aru_obj      = $self->{aru_obj};
    my $aru_no       = $params->{aru_no};
    $aru_obj         = ARU::BugfixRequest->new($aru_no)
        unless ($aru_obj);
    $aru_obj->get_details();

    my $request_id   = $params->{request_id};
    my $user_id      = $params->{user_id} || $aru_obj->{last_requested_by};
    my $job_id       = $params->{job_id};
    my $start_time   = $params->{start_time};
    my $retry_no     = $params->{retry_no} || 0;
    my $wait_time    = $params->{wait_time} || 1800;
    my $tran_name    = $params->{transaction_name};
    my $action       = $params->{action} || "check_farm_job_status";
    my $view_name    = $params->{ade_view_name} || $aru_no . "_em_install";
    my $log_fh       = $self->{aru_log};
    my $release = $aru_obj->{release};
    my $version = APF::PBuild::Util::get_version($release);

    my $preprocess = $self->{preprocess} ||
            APF::PBuild::PreProcess->new($params);
    $self->{preprocess} = $preprocess;
    my $gen_or_port;

    #
    # auto release for em ps1 java patches
    # fix for 17485263
    #
    my ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component, $abstract, $transaction_name);

    ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
        $category, $sub_component) =
            $preprocess->get_bug_details_from_bugdb($params->{bug});

    if (defined($aru_no) and $aru_no ne '')
    {
        $gen_or_port = "O";
    }
    else
    {
        $gen_or_port     = $preprocess->get_gen_port($params->{bug});
    }

    $self->{gen_port}   = $gen_or_port if (uc($gen_or_port) ne "O");
    my $pse = $preprocess->{pse} || $params->{bug};
    $log_fh->print("DEBUG: _check_farm_em_job_status pse = $pse \n");

    $self->{bugfix_request_id} = $aru_no;
    $params->{action_desc} = 'Check Results';
    $log_fh->print_header($params->{action_desc});

    $log_fh->print("Install Test check results for ARU $aru_no \n");

    my ($msg, $test_name);
    my $farm_job_status;
    my $farm = APF::PBuild::FarmJob->new({bugfix_req_id   => $aru_no,
                                          request_id       => $request_id,
                                          log_fh           => $log_fh,
                                          view_name        => $view_name,
                                          bug              => $pse,
                                          transaction_name => $tran_name,
                                          user_id          => $user_id,
                                          job_id           => $job_id,
                                          wait_time        => $wait_time,
                                          start_time       => $start_time,
                                          retry_no         => $retry_no });

    if ($farm->skip_farm() && !ConfigLoader::runtime("demo"))
    {
        $log_fh->print("Install Test Farm Job is skipped for the $aru_no.\n");
        return;
    }

    my $farm_status  = $farm->check_status();
    my $farm_log_loc = $farm->get_farm_log_location();

    $log_fh->print("\n\nFarm Job ID: $job_id \n" .
                   "Farm Status: $farm_status \n" .
                   "Farm Log Location: $farm_log_loc \n");

    if ($farm_status =~ /running|preparing|wait/i)
    {
        $msg = "Install Test: Farm Job $job_id is $farm_status . APF " .
               "will retry after $wait_time seconds";
        $log_fh->print("$msg \n");

        $log_fh->print("ARU: $aru_no, Status: $aru_obj->{status_id} \n");

        ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                       $aru_obj->{status_id}, "",
                       ARU::Const::apf2_userid,
                       $msg);

        $farm->{action}       = $action;
        $farm->{build_type}   = "em_install";
        $farm->{process_desc} = "";
        $farm->{post_process} = "";

        die($msg);
    }
    elsif ($farm_status =~ /success|finished/i)
    {
        $farm_job_status = $farm->is_success();

        if ($farm_job_status == 1)
        {
            $test_name = "APF-FARM-SUCCESS";
            $msg       = "Farm job $job_id for EM Install Test completed " .
                         "successfully";
            $log_fh->print("$msg \n");
        }
        else
        {
             $test_name = "APF-FARM-FAIL";
             $log_fh->print("Farm job $job_id, Status: $farm_status \n");

             $msg = "Farm job $job_id for EM Install Test Failed, see log".
                 " files for more details. Farm Log Location: $farm_log_loc ";
         }
    }
    else
    {
        $test_name = "APF-FARM-FAIL";
        $log_fh->print("Farm job $job_id, Status: $farm_status \n");

        $msg = "Farm job $job_id for EM Install Test Failed, see log files " .
               " for more details. Farm Log Location: $farm_log_loc ";
    }

    $log_fh->print("ARU: $aru_no , Status: $aru_obj->{status_id} = \n");

    ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                   $aru_obj->{status_id}, "",
                   ARU::Const::apf2_userid,
                   $msg);

    #
    # Fix for 16870048, em farm jobs are not polled
    #
    my($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                      $self->{request_id});

    ARUDB::exec_sp('isd_request.add_request_parameter',
                       $self->{request_id},
                       "st_apf_build",$req_params.
                       "!log_loc:$farm_log_loc".
                       "!suc:$farm_job_status");


    #
    # Get the apply patch log ingo
    #
    my @apply_logs = glob("$farm_log_loc/*/applying_opatch.out");

    foreach my $file (@apply_logs)
    {
        chomp($file);
        my $apply_fh = new FileHandle($file);
        my @lines = $apply_fh->getlines();
        $apply_fh->close();

        $self->{aru_log}->print("Reading $file: \n");
        $self->{aru_log}->print(@lines);
        $self->{aru_log}->print("\n\n\n");
    }
    $self->_update_bug($pse, {status     => 52,
                             programmer => 'PATCHQ',
                             test_name  => $test_name,
                             body       => $msg });

    #
    # Update the bugdb.
    #
    #
    # auto release for em ps1 java patches
    #
    if ($farm_job_status == 1)
    {
        my $oms_rolling =
            $preprocess->get_transaction_property
               ($tran_name,'BACKPORT_OMS_ROLLING') || "NO";

        $log_fh->print("BACKPORT_OMS_ROLLING is $oms_rolling \n");
        $log_fh->print("UTILITY_VERSION is $utility_ver \n");

        my $pse_prod_rel = $aru_obj->{product_id} . '_' . $utility_ver;
        my $is_auto_rel = $preprocess->is_value_in_aru_params(
                           $pse_prod_rel, 'em_auto_release_versions');
        if ($is_auto_rel == 1 &&
            $oms_rolling eq "YES")
        {
            $log_fh->print("Releasing patch $aru_no \n");
            $log_fh->print("For pse $pse, and version $version \n");
            $self->release($aru_no,$pse,$version);
        }

    }

    $farm->extend_farm_log_life();
    $farm->cleanup_install_view($view_name);

    die($msg)
        if ($farm_status !~ /success|finished|running|preparing|wait/);
}


sub _check_farm_job_status
{
    my ($self, $params) = @_;
    $self->{force_retry} = 1;
    my $aru_no           = $params->{aru_no};
    my $request_id       = $params->{request_id};
    my $user_id          = $params->{user_id};
    my $job_id           = $params->{job_id};
    my $start_time       = $params->{start_time};
    my $retry_no         = $params->{retry_no} || 0;
    my $tran_name        = $params->{transaction_name};
    my $src_txn          = $params->{parent_trans};
    my $backport_bug     = $params->{bug};
    my $view_name        = $params->{ade_view_name} || $aru_no;
    my $log_fh           = $self->{aru_log};
    my $multiple_jobs    = $params->{multiple_jobs};
    my $prev_job_id      = $params->{prev_job_id};
    my $farm_on_null_txn = $params->{farm_on_null_txn};

    my $farm;
    my $preprocess      = APF::PBuild::PreProcess->new($params);
    $self->{preprocess} = $preprocess;

    #
    # fix for 16870048, 17036632 em poll farm jobs
    # call check_farm_em_job_status and return for
    # em products
    #
    my $aru_obj = new ARU::BugfixRequest($aru_no);
    $aru_obj->get_details();

    my $gen_or_port;
    $log_fh->print("aru is $aru_no \n");
    $log_fh->print("backport_bug is $backport_bug \n");
    $log_fh->print("param bug is $params->{bug} \n");
    $log_fh->print("gen_or_port is $self->{gen_or_port} \n");

    if ((defined($aru_no) and $aru_no ne '') && (!$backport_bug))
    {
        $gen_or_port = "O";
    }
    else
    {
        $gen_or_port     = $preprocess->get_gen_port($params->{bug});
    }

    $log_fh->print("gen_or_port is $gen_or_port \n");
    $self->{gen_port}   = $gen_or_port if (uc($gen_or_port) ne "O");

    $self->{bugfix_request_id} = $aru_no;
    my $is_em_product = $preprocess->is_em_product($aru_obj->{product_id});
    if ($is_em_product == 1 && $gen_or_port eq "O")
    {
       $self->_check_farm_em_job_status($params);
       return;
    }

    $params->{action_desc} = 'Check Results';
    $log_fh->print_header($params->{action_desc});

    $farm = APF::PBuild::FarmJob->new({bugfix_req_id   => $aru_no,
                                      request_id       => $request_id,
                                      log_fh           => $log_fh,
                                      view_name        => $view_name,
                                      bug              => $backport_bug,
                                      transaction_name => $tran_name,
                                      user_id          => $user_id,
                                      job_id           => $job_id,
                                      start_time       => $start_time,
                                      retry_no         => $retry_no,
                                      backport_bug     => $params->{bug} });

   $farm->{source_trans} = $src_txn;
   $farm->{process_desc} = $params->{process_desc} || "Backport";
   $farm->{post_process} = $params->{post_process} || "end_backport_req";
   $farm->{is_hybrid}    = $params->{is_hybrid}    || 0;
   $farm->{build_type}   = $params->{build_type}   || "Regular";
   $farm->{parent_request_id} = $params->{parent_request_id} || 0;
   $farm->{last_bug_update_time} = $params->{last_bug_update_time} || '';

   $farm->{prev_job_id}      = $prev_job_id;
   $farm->{farm_on_null_txn} = $farm_on_null_txn;

   $self->{psu} = $farm->{psu};
    my ($farm_job_status,$farm_log_loc);
    unless( $farm->skip_farm() )
    {
        if ($multiple_jobs == 1)
        {
            $farm->{multiple_jobs} = 1;
            $farm->retry_multiple() unless ($farm->is_finished_multiple());
            $farm->extend_farm_log_life_multiple();
            $farm_job_status = $farm->is_success_multiple();
            $farm_log_loc = "Not available for multiple farm jobs";
        }
        else
        {
        $farm->retry() unless ($farm->is_finished());
        $farm->abort_job() if($farm->is_abort_needed());
        $farm->extend_farm_log_life();
        $farm_job_status = $farm->is_success();
        #
        # Log farm regression retries
        #
        $farm->log_farm_retry_count();
        $farm_log_loc = $farm->get_farm_log_location();
        }

        my($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                                                  $self->{request_id});

        ARUDB::exec_sp('isd_request.add_request_parameter',
                       $self->{request_id},
                       "st_apf_build",$req_params.
                       "!log_loc:$farm_log_loc".
                       "!suc:$farm_job_status");
    }

    if(  $farm->skip_farm()  || $farm_job_status ||
         $params->{post_process} eq "post_process_branched_txn" )
    {
        $params->{action_desc} = ($self->{gen_port} eq 'I' ||
                                  $self->{gen_port} eq 'Z') ?
                                 "Submit MergeReq" :
                                 "Commit " . $params->{process_desc};
    }
    else
    {
        my $bug_body = "Farm Job $job_id didn't complete successfully\n".
            "Please check Farm Results Location:\n".
                "$farm_log_loc\n".
                    "for more details";

        $farm->update_bug($backport_bug,
                      {body => $bug_body}) if (uc($gen_or_port) ne "B");

     $params->{action_desc} = "Commit " . $params->{process_desc};

        $self->{error} = 1;
        $self->{errmsg} = $bug_body;

     #
     # $farm->{farm_failure} is the same one which apf uses
     # for handing over the transction to SE.
     #
     $self->{farm_failure} = $farm->{farm_failure};
     $self->{farm_new_diffs} = $farm->{farm_new_diffs};
     $self->{farm_zero_lrgs} = $farm->{farm_zero_lrgs};
     $self->{aru_obj}      = $farm->{aru_obj};
     $self->{workarea}     = $farm->{work_area};
     $self->{base_bug}     = $farm->{base_bug};
   }

   $self->{log_fh}   = $log_fh;
   $self->{farm_obj} = $farm;

   if ($params->{post_process} eq "post_process_branched_txn")
   {
     $self->_post_process_branched_txn($params);
   }
   else
   {
       my $rc = $farm->resubmit_farm_job();
       $farm->end_backport_req($params->{action_desc})
           if ($rc == 0);
   }

   return;
}

#
# Process Branched Files
#
sub _post_process_branched_txn {

  my ($self, $params) = @_;

  my $bugfix_request_id = $self->{bugfix_request_id} = $params->{aru_no};

  my @request_result;

  my $request_object = ARUDB::query_object('GET_BUILD_REQUEST_ID',
                                              $self->{request_id});


  my @request_results = $request_object->some_rows();
  my $count = scalar(@request_results);
  if ($count == 0)
  {
      $request_object =
          ARUDB::query_object('FIND_REQUEST_IDS',$self->{request_id},
                              $bugfix_request_id);
      @request_results = $request_object->some_rows();

  }

  my $parent_request_id;

  foreach my $request(@request_results){
    #
    # If the new apf request encountered.Save previous request and exit.
    #

    if ($request->[1] == ISD::Const::st_apf_build_type) {
      $parent_request_id =  $request->[0];
      last;
    }
  }

  $params->{request_id} =
        $parent_request_id if (defined($parent_request_id) &&
                              $parent_request_id ne "");

  my $preprocess        = APF::PBuild::PreProcess->new($params);

  $self->{preprocess}   = $preprocess;

  my $log_fh = $self->{aru_log};

  $preprocess->get_preprocess_data($bugfix_request_id);

  my $work_area = $preprocess->{work_area};
  my $aru_obj   = $preprocess->{aru_obj};
  my $ade       = $preprocess->{ade};
  my $pse       = $preprocess->{pse};
  my $blr       = $preprocess->{blr};
  my $basebug   = $preprocess->{bug};
  my $ver       = $preprocess->{utility_version};
  my $base_bug  = $preprocess->{base_bug};
  my $bugfix_id = $preprocess->{bugfix_id};

  my $is_hybrid        = $params->{is_hybrid};
  my $transaction_name = $params->{transaction_name};
  my $build_type       = $params->{build_type};

  $bugfix_request_id         = $aru_obj->{aru};
  $self->{bugfix_request_id} = $bugfix_request_id;

  my $wkr = APF::PBuild::PortBuild->new($aru_obj, $work_area,
                                        $log_fh, $is_hybrid,
                                        $bugfix_request_id,$blr,
                                        $basebug, $ver,
                                        $transaction_name);

  $wkr->{isd_request_id} = $self->{request_id};
  $wkr->{request_id} = $self->{request_id} || $params->{request_id};
  $wkr->{error}  = $self->{error};
  $wkr->{errmsg} = $self->{errmsg};
  $wkr->{view}   = $params->{ade_view_name};

  $wkr->{reopen_txn} = 1;
  $wkr->end_branched_txn($transaction_name,
                         $params->{ade_view_name},
                         $build_type);

  if ($params->{farm_job_final_status} ne "SUCCESS")
  {
      #my $bug_body = "Farm Job didn't complete successfully\n".
      #               "It failed with Error : $params->{farm_job_error_msg}\n".
      #               "Please check Farm Results \n".
      #               "for more details";

      #$farm->update_bug($backport_bug,
      #      {body => $bug_body}) if (uc($gen_or_port) ne "B");

      #$params->{action_desc} = "Commit " . $params->{process_desc};

      #$self->{error} = 1;
      #$self->{errmsg} = $bug_body;
      #$self->_update_bug($pse, {status        => 52,
      #                          programmer    => 'PATCHQ',
      #                          test_name     => $params->{farm_job_final_status},
      #                          tag_name      => $params->{farm_job_final_status},
      #                          body          => $bug_body });
      #die ("$bug_body");
   }

  #
  # Build the objects using the newly created Branched File(s)
  # Transaction
  #

  $wkr->port_build($bugfix_request_id,0,1,$transaction_name)
      if (lc($build_type) eq "regular");

  #
  # If the transaction has 32 bit objects then check
  # for the branched files. If the build type is Hybrid that
  # means we have processed both regular and hybrid objects
  #

  if ($is_hybrid) {
    if (lc($build_type) eq "regular") {

      #
      # We already processed for Regular build, Check
      # for Hybrid build
      #

        my $return_code = $wkr->preProcess($bugfix_request_id,1);
        return
            if ($return_code == PB::Config::check_farm_job_status);

      #
      # Either a Branched File(s) transaction already exist
      # or there are no Branched File(s)
      #

        $wkr->port_build($bugfix_request_id,1,$return_code,undef);

    } elsif (lc($build_type) eq "hybrid") {

      #
      # If we are here means, there are Hybrid objects and
      # Branched File(s) transaction has been created. Build
      # the objects using the new Transaction

        $wkr->port_build($bugfix_request_id,1,1,$transaction_name);
    }
  }

  #
  # calling PostProcessing action
  #
  $params->{aru_dir}  = $self->{aru_dir};
  $params->{aru_log}  = $self->{aru_log};
  $params->{blr}      = $blr;
  $self->{aru_dir}    = $work_area;
  $self->_postprocess($params);
  return;
}

# get the list of the 32 bit objects by processing the template file
sub get_32bit_objects
{
    my ($self) = @_;
    my $log_fh = $self->{aru_log};
    my $pse = $self->{pse};
    $self->{bit_32} = "";

    my $tmpl_file = "$self->{pse}" . TMPL_EXT;
    open (TEMPLATE_FILE, $tmpl_file) ||
        die "\n\nERROR: Cannot open $tmpl_file\n";
    $log_fh->print("\n+-----TEMPLATE FILE CONTENT-----+\n");
    while (<TEMPLATE_FILE>)
        {
            chomp;
            # Find if this has 32 bit objects
            if (m/ARCHIVE_LIST/)
            {
                if (m/:32\//)
                {
                   $log_fh->print("Patch has 32 bit object\n");
                   s/.*=//;
                   s/["{}]//g;
                   my @arch_triplets = split(/,/, $_);
                   foreach my $one_triplet (@arch_triplets)
                   {
                      my ($lib, $file)= split(/:/,$one_triplet);
                      $_ = $file;
                      s/32\///;
                      s/\s//g;
                      s/.o$/.c/;
                      # we only have the name of the file, not the
                      # full path to the file
                      $self->{bit_32} .= "  $_,"
                          unless ($self->{bit_32} =~ /$_/);
                   }
                }
            }
        }
    close (TEMPLATE_FILE);
    if ($self->{bit_32} ne "")
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub process_template
{
    my ($self) = @_;
    my $log_fh = $self->{aru_log};
    my $pse = $self->{pse};
    $self->{relink_cmd} = "Executables relinked with the following commands:\n";
    my $relink_txt = "";

    my $tmpl_file = "$self->{bugfix_request_id}" . TMPL_EXT;
    open (TEMPLATE_FILE, $tmpl_file) ||
        die "\n\nERROR: Cannot open $tmpl_file\n";
    $log_fh->print("\n+-----TEMPLATE FILE CONTENT-----+\n");
    while (<TEMPLATE_FILE>)
        {
            chomp;
            if (m/MAKE_TRIPLETS/)
            {
               s/.*=//;
               s/["{}]//g;
               my @all_triplets = split(/,/, $_);
               foreach my $one_triplet (@all_triplets)
               {
                  my ($dir, $mkfile, $target) = split(/:/,$one_triplet);
                  $target =~ s/^i// if ($target =~ /^i/);
                  if ($relink_txt !~ $target)
                  {
                      $relink_txt .= "  cd \$ORACLE_HOME\/$dir; ";
                      $relink_txt .= "  make -f $mkfile $target\n";
                  }
               }
            }
        }
     close (TEMPLATE_FILE);
     if ($relink_txt eq "")
     {
        $self->{relink_cmd} .= "None";
     }
     $self->{relink_cmd} .= $relink_txt ;
}

#
# This API will apply the built patch on clean OH for manually uploaded patches
#
sub _testmanual
{
    my ($self, $params) = @_;
    $self->{testmanual} = 1;
    $self->_test($params);
}

#
# This API will run the Product QA tests
#
sub _qatest
{
    my ($self, $params) = @_;

    my $aru_no     = $params->{aru_no};
    my $request_id = $params->{request_id};
    my $log_fh     = $self->{aru_log};
    $self->{bugfix_request_id} = $aru_no;

    my $aru_obj = new ARU::BugfixRequest($aru_no);

    my ($pse) = ARUDB::single_row_query("GET_PSE_BUG_NO", $aru_no);
    $pse ||= $params->{bug};


    my $it = APF::PBuild::QAInstallTest->new
        (
     {aru_obj       => $aru_obj,
      product_id    => $aru_obj->{product_id},
      bugfix_req_id => $aru_obj->{aru},
      pse           => $pse,
      request_id    => $request_id,
      patch_type    => ARU::Const::ptype_cumulative_build,
      log_fh        => $log_fh});

    $it->run_qa_test();

}

#
# skip_header is called to fidn out if printing same header
# in the next iteration of a suspended req needs to be skipped.
#

sub skip_header
{
    my ($self, $params) = @_;
    my $log_fh     = $self->{aru_log};
    if(defined $params->{skip_header})
    {
     #
     # If the request was suspended earlier ,
     # change the filename so that the error log is created without
     # _<digit> appended . Otherwise log viewer errors out
     # it is a flow in isd_request package.
     # this is kind of a workaround till isd_request fixes this issue.
     #

     my ($status_code) =
         ARUDB::single_row_query("WAS_SUSPENDED_CHECK", $params->{request_id});

     my $is_req_valid = 1;
     if (defined $self->{group_id} && $self->{group_id} ne "")
     {
         my ($apf_request_status) =
             ARUDB::single_row_query("IS_REQUEST_IN_PROGRESS",
                                     $params->{request_id},
                                     ISD::Const::isd_request_stat_busy,
                                     $self->{group_id});

         if ($apf_request_status > 0)
         {
             $is_req_valid = 1;
         }
         else
         {
             $is_req_valid = 0;
         }
         $self->{aru_log}->print("DEBUG: skip_header1: ".
                                 "Request ID: $params->{request_id}".
                                 ",$self->{group_id} \n");
     }

     $self->{aru_log}->print("DEBUG: skip_header: ".
                             "$status_code,$is_req_valid \n");
     if($status_code eq ISD::Const::isd_request_stat_susp &&
        $is_req_valid == 1)
     {
       my $request_log =
        $self->{aru_log}->get_task_log_info(format => "absolute");
       $request_log=~s/\.log$//;
       $self->{aru_log}->{filename}=$request_log;
       return 1;
     }
     else
     {
      #
      # If the request was not suspended earlier , it is either
      # coming from a restart/retry that was errored out earlier
      # or the server was bounced
      # hence remove skip_header param and signal to print the header.
      #
       my $req_params = "";
       foreach  my $key(sort keys %{$params})
       {
         $req_params.="!$key:$params->{$key}"
            if( ( defined $key ) && ( $key!~/SKIP_HEADER/i ) ) ;
       }

       $req_params=~s/^!//;
       ARUDB::exec_sp('isd_request.add_request_parameter',
                       $params->{request_id},
                       "st_apf_build",$req_params);
       $self->{aru_log}->print("status 123" );
       return 0;
     }
    }
    else
    {
       return 0;
    }
}

#
# Validate SQL file metadata of CI txn's
# submitted for mergereq.
# Also validates BACKPORT_SQL* properties of the txn.
#
sub _validate_mergereq_txn
{
  my ($self, $params) = @_;

  $self->{aru_log}->print_header("Validate Transaction");
  $self->{aru_log}->print("Validating txn : $params->{txn_name}\n");

  my $base =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                     request_id => $self->{request_id},
                                     aru_obj => undef,
                                     log_fh => $self->{aru_log});

  #
  # Getting txn metadata with retry logic
  #
  my $ade  = SrcCtl::ADE->new('filehandle' => $self->{aru_log});
  my $bp;
  for (my $x=0;$x!=APF::Config::describetrans_retry_val;$x++)
 {
  $ade->get_transaction_metadata($params->{txn_name});
  if($ade->{transaction}->{BACKPORT_BUG_NUM})
  {
   $bp = $ade->{transaction}->{BACKPORT_BUG_NUM};
   $self->{aru_log}->print("BACKPORT BUG NUM1 : $bp\n");
   last ;
  }
  else
  {
   $self->{aru_log}->print("Retry Count : $x\n");
   sleep APF::Config::describetrans_interval ;
   $ade->{desc_trans_output} = {};
  }
 }
  my $bp = $ade->{transaction}->{BACKPORT_BUG_NUM};
  my $label =  $ade->{transaction}->{BASE_LABEL};
  $self->{aru_log}->print("BACKPORT BUG NUM : $bp\n");
  $self->{aru_log}->print("LABEL : $label\n");

  #
  # creating view ,temporary txn and fetching the backport txn
  #
  my $view_name = $bp."_mergereq_".$$;
  my $ade_root_path = PB::Config::ade_root_path;
  my $view_storage = $ade_root_path . "/view_storage";
  my $txn_storage = $ade_root_path . "/txn_storage";
  $ade->create_view($label,$view_name, (force => 'Y',
                                        view_storage => $view_storage));
  my $ade_view = $ade->use_view($view_name,
                                  ('filehandle' => $self->{aru_log},
                                   'timeout' => 5000));
  my $ade_view_root = $ade_view->get_view_directory();
  my $view_txn_name =  $bp . "_mergereqtxn_" . $$ ;

  my $fetchfile = $self->{aru_dir}."/".$bp."_fetch_files.sh";
  my $ffh = new FileHandle "> $fetchfile" ||
            die("Unable to write to file $fetchfile: $!");
  print $ffh "cd $ade_view_root \n";
  print $ffh "ade begintrans  $view_txn_name\n";
  print $ffh "ade fetchtrans $params->{txn_name}\n";
  close($ffh);

  $ade_view->do_cmd("chmod 0777 $fetchfile;$fetchfile",
                    ('timeout' => 5000),('filehandle' => $self->{aru_log}));

  #
  # Getting txn files
  #
  my $file_ref_with_vers = $base->get_transaction_files($ade,
                                        $params->{txn_name});
  my $file_ref = [];
  foreach my $file (@$file_ref_with_vers)
  {
   my ($file_name, $version) = split("@@", $file);
   push(@$file_ref,$file_name);
  }

  #
  # Validating File Metadata
  #
  my $trig = APF::PBuild::ADEAPFTriggers->new();
  $trig->{syscmd} = $base->{system};
  $trig->{ade_view_root} = $ade_view_root;
  my $phase_xml = $trig->determine_phase_xml();
  my $error_str = {};
  foreach my $file_name (@$file_ref)
  {
   my ($src_path, $src_name) = ($file_name =~ /(.*)\/(.*)/);
   if (($src_name =~ m/\.sql|\.pls|\.plb|\.pkh|\.pkb|recovery/) &&
       ($src_path  =~ m/^t[k-o].*|^tp[a-u].*|\btest\b/))
   {
    print "Skipping validation for $file_name since ".
          "it is from a test directory \n";
    next;
   }

   $self->{aru_log}->print("SQL Validation of $file_name started \n");

   my ($sql_validation_err, $sql_validation_err_msg) =
         $trig->validate_sql_file($file_name,$file_ref,$phase_xml,$ade,"Z");
   $error_str->{$file_name} = $sql_validation_err_msg if($sql_validation_err);
  }

  #
  # Validating BACKPORT_SQL* properties
  #
  my ($bpsql_validation_err, $bpsql_validation_err_msg) =
             $trig->validate_all_backport_sql_props($ade);
  $error_str->{'bp_sql_issues'} = $bpsql_validation_err_msg
                                if($bpsql_validation_err);

  #
  # aborting and destroying the temporary txn
  #
  $fetchfile = $self->{aru_dir}."/".$bp."_fetch_files_2.sh";
  $ffh = new FileHandle "> $fetchfile" ||
              die("Unable to write to file $fetchfile: $!");
  print $ffh "cd $ade_view_root \n";
  print $ffh "ade unco -all \n";
  print $ffh "ade unbranch -all -force\n";
  print $ffh "ade aborttrans -purge -force \n";
  print $ffh "ade destroytrans $view_txn_name -force -rm_properties  \n";
  close($ffh);

  $ade_view->do_cmd("chmod 0777 $fetchfile;$fetchfile",
                   ('timeout' => 5000),('filehandle' => $self->{aru_log}));

  #
  # Destroying the view
  #
  $ade->destroy_view($view_name);

  #
  # Creating XML o/p with list of errors found
  #
  my $doc = XML::LibXML::Document->new('1.0', 'utf-8');
  my $root = $doc->createElement("validate_txn");
  $root->setAttribute('txn_name'=> $params->{txn_name});
  $root->setAttribute('backport_bug'=> $bp);

  my $error_found = 0;
  foreach my $file (sort keys %{$error_str})
  {
   foreach my $err (@{$error_str->{$file}})
   {
    $error_found = 1;
    my $tag = $doc->createElement("error");
    $tag->appendTextNode($err);
    $root->appendChild($tag);
   }
  }

  #
  # Displaying the XML o/p in the log and failing the flow
  # in case error found.
  # Error String should start with 'SQL validation through mergereq'
  # since this error message is used in handle_failure function to
  # validate if the call will be returned without updating the bug.
  #
  if($error_found)
  {
   $doc->setDocumentElement($root);
   $self->{aru_log}->print("\n\n*************************\n");
   $self->{aru_log}->print("Errors from Validation\n");
   $self->{aru_log}->print($doc->toString(1));
   $self->{aru_log}->print("*************************\n\n");
   die "SQL validation through mergereq Failed.".
       " Please check errors in xml format".
       " (inside error tags) in the last logfile\n";
  }
  else
  {
   $self->{aru_log}->print("\nSQL validation through mergereq ".
                           "completed successfully for".
                           " txn $params->{txn_name} \n");
  }

}

sub _poll_jenkins_installtest
{
	my ($self, $params) = @_;
	$self->{log_fh}->print("_poll_jenkins_installtest \n");

	my $it  = APF::PBuild::JenkinsInstallTest->new($params);

	$self->{log_fh}->print("calling poll_jenkins \n");
	$it->poll_jenkins();
}

sub _poll_l1_status
{
 my ($self, $params) = @_;

 my $fmw12c  = APF::PBuild::FMW12c->new($params);
 $fmw12c->{aru_log} = $self->{aru_log};

 $fmw12c->poll_l1($params->{BLR});
}

sub _submit_hudson_build
{
 my ($self, $params) = @_;

 my $fmw12c  = APF::PBuild::FMW12c->new($params);
 $fmw12c->{aru_log} = $self->{aru_log};
 $fmw12c->submit_hudson_rest_api($params->{BLR});
}

sub _trigger_cloud_test_job
{
 my ($self, $params) = @_;

 my $aru = $params->{ARU};
 my $pse = $params->{PSE};

 my $aru_obj = new ARU::BugfixRequest($aru);
 $aru_obj->get_details();

 my $orch_ref =
            APF::PBuild::OrchestrateAPF->new({request_id    => $self->{request_id},
                                        log_fh        => $self->{aru_log},
                                        pse           => $pse});

 $orch_ref->{aru_obj} = $aru_obj;
 $orch_ref->{utility_version} = $aru_obj->{release};
 $orch_ref->{send_build_status} = 1;
 $orch_ref->{blr} = $params->{BLR};
 $orch_ref->post_fmw12c_data($pse, "build_status",
                                    $self->{request_id},
                                    ISD::Const::st_apf_build_type);
}

sub _auto_template_request
{
    my ($self, $params) = @_;
    $self->{aru_log}->print_header("Create Template")
        unless($self->skip_header($params));
    $params->{release} = uc($params->{release});
    my $psu_it = new APF::PBuild::InstallTest({
                                        bugfix_req_id => $params->{psu_aru},
                                        request_id    => $self->{request_id},
                                        log_fh        => $self->{aru_log},
                                        release       => $params->{release},
                                        platform_id   => $params->{platform_id},
                                        create_psu_template => 0,
                                        params        => $params});

    #
    # To Create the soft link for the exact minimum opatch version opatch path
    #
    my $base =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                       request_id => $self->{request_id},
                                       pse    => $params->{psu_aru},
                                       aru_obj => undef,
                                       log_fh => $self->{aru_log});
    $self->{base_ref} = $base;

    my $timestamp  = $base->get_datetime();
    $timestamp =~s/\s//g;
    $timestamp =~s/\-//g;
    $timestamp =~s/://g;

    my $min_opatch_ver = $base->get_min_opatch_ver($params->{release_id},
                                                   $params->{release});
    if (defined $min_opatch_ver && $min_opatch_ver ne "")
    {
        #
        # Create soft link in HQ worker host
        #
        if (ConfigLoader::runtime("production")) {
            $self->create_link_for_opatch_dir($min_opatch_ver,
                                               APF::Config::ade_hq_wkr_host,
                                               APF::Config::ade_hq_opatch_base,
                                               'HQ',
                                               $params->{release_id},
                                               $params->{release});
        }

        #
        # Create soft link in UCF worker host
        #
        $self->create_link_for_opatch_dir($min_opatch_ver,
                                            APF::Config::ade_ucf_wkr_host,
                                            APF::Config::ade_ucf_opatch_base,
                                            'UCF',
                                            $params->{release_id},
                                            $params->{release});
    }

    $psu_it->{psu_release_version} = $params->{release};
    $psu_it->{create_psu_template} = $psu_it->_create_psu_template_name(
                                     $params->{release},
                                     $params->{platform_id});
    $psu_it->{psu_template_name}   = $psu_it->{create_psu_template};
    $psu_it->{psu_label_id} = $params->{psu_label_id};
    $psu_it->{auto_template_release} = $params->{release};
    $psu_it->{templ_gen_mode} = uc($params->{templ_gen_mode});

    if ((!$params->{curr_tmpl_name}) && ($params->{curr_tmpl_id})) {
      $params->{curr_tmpl_name} =
            $psu_it->_get_ems_template_name($params->{curr_tmpl_id});
    }
    $psu_it->{curr_tmpl_name} = uc($params->{curr_tmpl_name});

    #$psu_it->{temp_tmpl_name} = "XX".uc($params->{curr_tmpl_name});

    my $tmpl_suffix = uc($psu_it->{curr_tmpl_name});
    $tmpl_suffix =~ s/XX//g;
    $tmpl_suffix =~ s/_RDBMS_FRESH//g;
    $tmpl_suffix =~ s/^\s+|\s+$//g;
    $psu_it->{temp_tmpl_name} = $tmpl_suffix."_".$timestamp;

    $psu_it->{user_id} = $params->{user_id};
    $psu_it->send_notification_for_auto_template(1)
        unless($self->skip_header($params));
    $psu_it->{throttle_req_type} = ARU::Const::throttle_install_type;

    my ($psu_label_name) = ARUDB::single_row_query
                                  ('GET_LABEL_NAME_FROM_LABEL_ID',
                                   $params->{psu_label_id});

    $psu_it->{psu_label_name} = $psu_label_name;
    $self->{log_fh}->print("DEBUG: TEMPL NAME: ".
                               "$psu_it->{curr_tmpl_name} \n");

    if ($psu_it->{psu_template_name} ne ""
        && $psu_it->{psu_template_name} ne APF::Config::inprogress_ems_tmpl
        && $psu_it->{psu_template_name} ne APF::Config::no_ems_tmpl)
    {
        $self->{log_fh}->print("DEBUG: PSU TEMPL GEN MODE : ".
                               "$psu_it->{templ_gen_mode}, ".
                               "$psu_it->{psu_template_name} \n");

        #$psu_it->{temp_tmpl_name} = "XX".$psu_it->{psu_template_name};
        my $cur_tmpl_suffix = uc($psu_it->{curr_tmpl_name});
        $cur_tmpl_suffix =~ s/XX//g;
        $cur_tmpl_suffix =~ s/_RDBMS_FRESH//g;
        $cur_tmpl_suffix =~ s/^\s+|\s+$//g;

        $psu_it->{temp_tmpl_name} = $cur_tmpl_suffix."_".$timestamp;
        #if ($psu_it->{templ_gen_mode} eq "REGENERATE")
        #{
            my $rc = $psu_it->run_ems_update_env(
                                                 $psu_it->{psu_template_name},
                                                 $psu_it->{temp_tmpl_name});
        #}
    }

    if ($psu_it->{curr_tmpl_name} ne ""
        && $psu_it->{curr_tmpl_name} ne $psu_it->{psu_template_name}
        && $psu_it->{curr_tmpl_name} ne APF::Config::inprogress_ems_tmpl
        && $psu_it->{curr_tmpl_name} ne APF::Config::no_ems_tmpl)
    {
        #$psu_it->{temp_tmpl_name} = "XX".$psu_it->{curr_tmpl_name};
        my $cur_tmpl_suffix = uc($psu_it->{curr_tmpl_name});
        $cur_tmpl_suffix =~ s/XX//g;
        $cur_tmpl_suffix =~ s/_RDBMS_FRESH//g;
        $cur_tmpl_suffix =~ s/^\s+|\s+$//g;

        $psu_it->{temp_tmpl_name} = $cur_tmpl_suffix."_".$timestamp;
        $self->{log_fh}->print("DEBUG: Current Template Details: MODE : ".
                               "$psu_it->{templ_gen_mode}, ".
                               "$psu_it->{curr_tmpl_name} \n");
        if ($psu_it->{templ_gen_mode} eq "REGENERATE")
        {
            my $rc = $psu_it->run_ems_update_env(
                                                 $psu_it->{curr_tmpl_name},
                                                 $psu_it->{temp_tmpl_name});
        }

        #if ($psu_it->{templ_gen_mode} eq "REGENERATE")
        #{
        #    my $rc = $psu_it->run_ems_update_env(
        #                                         $psu_it->{curr_tmpl_name},
        #                                         $psu_it->{temp_tmpl_name});
        #}
    }

    my $psu_rc = $psu_it->run_install();
    $psu_it->free_throttle_resource($psu_it->{request_id},
                                    ISD::Const::isd_request_stat_succ);

    if ( $psu_it->{templ_available} )
    {
       $psu_it->seed_install_test_host();
       $self->{aru_log}->print("\t Seeding template for ".
                         "label $self->{psu_label_id}\n");
       $psu_it->seed_template($params->{psu_label_id},
                              $psu_it->{psu_template_name});

       if(defined $params->{psu_label_id_32})
       {
         $self->{aru_log}->print("\t Seeding template for hybrid label ".
                          "$params->{psu_label_id_32}\n");
         $self->seed_template($params->{psu_label_id_32},
                              $psu_it->{psu_template_name});
       }
       if(defined $psu_it->{psu_label_id_32})
       {
         $self->{aru_log}->print("\t Seeding template for hybrid label ".
                          "$psu_it->{psu_label_id_32}\n");
         $self->seed_template($psu_it->{psu_label_id_32},
                              $psu_it->{psu_template_name});
       }
        $psu_it->seed_base_template_for_gen_label($params->{psu_label_id},
                              $psu_it->{psu_template_name},
                              $params->{release_id},
                              $params->{platform_id});
        $self->{aru_log}->print("\t Template Available: ".
                                "$psu_it->{psu_template_name}\n");

       if ($psu_it->{templ_gen_mode} eq "REGENERATE")
       {
           $psu_it->{env_name} = $psu_it->{temp_tmpl_name};
           my $rc =  $psu_it->run_ems_delete_env();
           unless ($rc) {
               # Try with ignore errors=yes
               my $rc1 = $psu_it->run_ems_delete_env(
                                          "--param ignore_errors=yes");
           }
       }

        $psu_it->send_notification_for_auto_template(2)
            unless($self->skip_header($params));
     }
     else
     {
        my $err_msg = "Auto-generation of Template ".
                      " $psu_it->{psu_template_name} Failed";
        if ($psu_it->{curr_tmpl_name} ne "T_PROGRESS_INSTALLTST"
            && $psu_it->{curr_tmpl_name} ne "T_NO_INSTALLTST")
        {
            if ($psu_it->{templ_gen_mode} eq "REGENERATE")
            {
                my $rc = $psu_it->run_ems_update_env(
                                                 $psu_it->{temp_tmpl_name},
                                                 $psu_it->{curr_tmpl_name});

                $err_msg = "Auto-regeneration of Template ".
                    " $psu_it->{psu_template_name} Failed.".
                        " So, restoring the oldtemplate";
            }
        }

        $psu_it->send_notification_for_auto_template(3,$err_msg);
        die "$err_msg\n";
     }

}

#
# subroutine to get aru status when the install test started
# bug 16669527
#
sub _get_aru_status_before_test
{
 my ($self, $params) = @_;

 my $log_fh     = $self->{aru_log};
 my ($req_par) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                                         $params->{request_id});
 my ($orig_status) = ($req_par=~/aru_sts_on_tst:(\d+)/);
 unless($orig_status)
 {
  ($orig_status) = ARUDB::single_row_query("GET_RELEASED_ARU_STATUS",
                                           $params->{aru_no});
 }

 unless($req_par=~/aru_sts_on_tst:(\d+)/)
 {
  $req_par =~s/!aru_sts_on_tst://g;
  $req_par.= "!aru_sts_on_tst:".$orig_status;
  ARUDB::exec_sp('isd_request.add_request_parameter', $params->{request_id},
                "st_apf_build",$req_par);
 }

 $self->{aru_orig_status} = $orig_status;
}

#
# This API will apply the built patch on clean OH
#
sub _test
{
    my ($self, $params) = @_;

    my $aru_no     = $params->{aru_no};
    my $request_id = $params->{request_id};
    my $log_fh     = $self->{aru_log};
    $self->{bugfix_request_id} = $aru_no;

    my ($it, $rc);

    # rc_tstfwk is a var for tstfwk
    my $rc_tstfwk;
    my ($pse) = ARUDB::single_row_query("GET_PSE_BUG_NO", $aru_no);
    $pse ||= $params->{bug};
    my $testmanual = 0;
    $testmanual = 1
        if (defined $self->{testmanual} && $self->{testmanual} ne "");

    #
    # For manual uploads, auto installtest shouldn't get kicked off
    # ref bug:27555838
    #
    my ($patch_type) = ARUDB::single_row_query('GET_PATCH_TYPE',
                              $aru_no);

    if ($patch_type == ARU::Const::ptype_cumulative_build &&
        $params->{bug} eq '')
    {

        $log_fh->print("No Auto Installtest for manual upload bundles\n");
        return;
    }

    $self->suspend_retry_request($params); # checks and suspends

    $it = new APF::PBuild::InstallTest({bugfix_req_id => $aru_no,
                                        request_id    => $request_id,
                                        log_fh        => $log_fh,
                                        pse           => $pse,
                                        testmanual    => $testmanual,
                                        params        => $params});
    $it->{sql_patch_only} = $params->{sql_patch_only} || "";

    if (! defined APF::Config::enable_throttling_pse ||
        APF::Config::enable_throttling_pse != 1)
    {
        ARUDB::exec_sp("aru.apf_request_status.update_throttle_requests");
    }

    my $release_id = $it->{aru_obj}->{release_id};

    my $test_comment = "Install Test";
    my $emcc_enabled = PB::Config::emcc_enabled_release_platforms;

    my $aru_obj = $it->{aru_obj};
    my $test_type;

    $self->{emcc_installtest} =
           APF::PBuild::Util::is_emcc_installtest($aru_obj);

    my $sql_patch_only = $params->{sql_patch_only} || "";

    my $gi_bundle = $it->check_for_gi_bundles();
    $self->{is_bundle_patch} = $it->{is_bundle_patch};

    if ($gi_bundle)
    {
        my $release = $it->{aru_obj}->{release};
        my $version = APF::PBuild::Util::get_version($release);

        $log_fh->print("Install test skipped for $pse and " .
                       "for version $version \n");
        $log_fh->print("Calling check_install_test release API: " .
                       "$pse, $it, $aru_no, $version \n");
        $self->release($aru_no,$pse,$version);
        return;
    }

    $it->is_fmw12c();
    #
    # for FMW12c process
    #
    if ($it->{is_fmw12c})
    {
        my $orch_ref =
            APF::PBuild::OrchestrateAPF->new({request_id    => $request_id,
                                        log_fh        => $log_fh,
                                        pse           => $pse});

        $orch_ref->{aru_obj} = $aru_obj;
        $orch_ref->{utility_version} = $aru_obj->{release};
        $orch_ref->post_fmw12c_data($pse, "build_status",
                                    $request_id,
                                    ISD::Const::st_apf_build_type);
    }

    $log_fh->print("Validating datapatch drivers and release\n");
    $log_fh->print("Release : $aru_obj->{release},".
                   "base bug : $aru_obj->{bug},".
                   "request id : $request_id\n");

    my ($datapatch, $pre12) = $it->is_datapatch(
                                  {release    => $aru_obj->{release},
                                   request_id => $request_id});

    $log_fh->print("datapatch : $datapatch, $pre12 \n");

    if ($datapatch && $pre12)
    {
        my $dp_driver = $it->validate_datapatch_drivers();
        if($dp_driver)
        {
            $log_fh->print("Will drive pre 12.1 datapatch(sqlpatch) test. \n");
            $it->{pre12_datapatch} = 1;
            $log_fh->print("Disabling EMCC Install Test.\n");
            $self->{emcc_installtest} = 0;
        }
        else
        {
            die "--datapatch was passed but patch file does not contain ".
                "datapatch drivers\n";
        }
    }
    else
    {
        $it->{pre12_datapatch} = 0;
    }

    if ($self->{emcc_installtest})
    {
        $test_comment = "Install Test Flow";
        $self->{emcc_tag} = "APF-EMCC-INSTALLTEST-SUCCESS";
        $test_type = "data_driven_tests";
        $it->{emcc_attempted} = 0;
    }

    my ($isd_req_comments);
    my $throttling_enabled = 0;
    my $is_resumed_req = 0;
    my ($is_fmw11g) = $it->is_fmw11g();
    if ($release_id !~
        /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        if ($self->skip_header($params))
        {
            my ($is_patch_released) = ARUDB::single_row_query
                                        ('IS_PATCH_RELEASED',
                                         $aru_no);

            if ($is_patch_released == 1)
            {
                $log_fh->print("DEBUG: Patch is already released to".
                               " the customer \n");
                return;
            }

            if (defined PB::Config::enable_throttling_pse &&
                PB::Config::enable_throttling_pse == 1 &&
                (! defined $is_fmw11g || $is_fmw11g != 1))
            {
                $throttling_enabled = 1;
                ($isd_req_comments) = ARUDB::single_row_query
                                        ('GET_APF_REQ_STATUS_COMMENTS',
                                         $request_id);
                if (defined $isd_req_comments &&
                 $isd_req_comments eq APF::Const::host_quota_unavailable)
                {
                    $is_resumed_req = 1;
                }
            }

        }
    }

    #
    # Store original status
    #
    $self->_get_aru_status_before_test($params);

    unless($self->skip_header($params))
    {
        $log_fh->print("ARU: $aru_no, Status: Internal --\n");

        my ($base_bug) = ARUDB::single_row_query
            ('GET_BASEBUG_FOR_PSE', $pse);
        my $product_id = $it->{aru_obj}->{product_id};

        my ($utility_ver) = ARUDB::single_row_query
            ('GET_UTILITY_VERSION', $pse);

        my $raise_exception = "y";
        my $ignore_blr_status = "y";

        my $blr = ARUDB::exec_sf('aru.bugdb.get_blr_bug',
                                 $base_bug, $utility_ver,
                                 ['boolean',$raise_exception],
                                 $product_id,
                                 ['boolean',$ignore_blr_status]);


        my ($blr_status, $blr_prod_id, $blr_priority) =
            ARUDB::single_row_query("GET_BUG_DETAILS_FROM_BUGDB", $blr);

        $log_fh->print("P1_PSE_EXCEPTION: \n Base_Bug: $base_bug,\n ".
                       "Release ID: $release_id,\n".
                       "BLR: $blr,\n BLR Status: $blr_status, \n".
                       "Blr Product ID: $blr_prod_id, \n".
                       "Blr Priority: $blr_priority \n");

        my $p1_pse_exception = 0;
        my ($req_enabled) = ARUDB::single_row_query("GET_COMPAT_PARAM",
                                                  'P1_PSE_EXCEPTION_PRODUCT');

        $blr_prod_id =~ s/\s//g;
        $blr_status =~ s/\s//g;
        $blr_priority =~ s/\s//g;

        $self->{log_fh}->print("\nRequest Enabled for $req_enabled, ".
                               "$blr_priority, $blr_status, $blr_prod_id \n");

        my $update_bug_internal = 0;
        $it->{product_id} = $it->{aru_obj}->{product_id};
        $it->{release_id} = $it->{aru_obj}->{release_id};
        $it->is_parallel_proc_enabled();

        my $fail_pse = 0;
        if ($it->{enabled} == 1)
        {
            $self->{log_fh}->print("DEBUG: Parallel processing is enabled \n");
            my ($p_severity) = ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                                       $pse);
            if (! ($it->{only_p1} == 1 && $p_severity > 1))
            {
                if ($blr_status == 11)
                {
                    #
                    # Update the comments for this ARU
                    #
                    ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                                   ARU::Const::patch_ftped_internal, "",
                                   ARU::Const::apf2_userid,
                                   "Starting $test_comment");
                    $update_bug_internal = 1;
                }
                elsif ($blr_status == 52)
                {
                    $fail_pse = 1;
                }
            }
        }

        if ($fail_pse == 1)
        {
            die("ERROR: Halting the PSE as the BLR is failed. \n");
        }

        if ( $req_enabled =~ /$blr_prod_id/ &&
             $blr_priority == 1 && $blr_status == 11 && $aru_no ne '' &&
             $update_bug_internal == 0)
        {
            ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                           ARU::Const::patch_on_hold, "",
                           ARU::Const::apf2_userid,
                           "P1_PSE_Exception, Starting $test_comment");

        }
        else
        {

            #
            # Update the comments for this ARU
            #
            ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                           ARU::Const::patch_ftped_internal, "",
                           ARU::Const::apf2_userid,
                           "Starting $test_comment")
                    if ($update_bug_internal == 0);
        }

        $log_fh->print_header("Invoke $test_comment")
            if ($is_resumed_req == 0);
    }

    my $die_err_msg;
    $it->{throttle_req_type} = ARU::Const::throttle_install_type;

    $log_fh->print("platform id : $aru_obj->{platform_id} \n");
    if($aru_obj->{platform_id} == ARU::Const::platform_metadata_only){
        $log_fh->print("Calling is_system_subpatch for metadatapatch\n");
        $it->is_system_subpatch(1); 
    }


    if ($ENV{APF_DEBUG} =~ /skip_install/)
    {
        $rc = 1;
        $log_fh->print("Skip applying the patch as APF_DEBUG is set\n");
    }
    else
    {
        eval
        {
            #
            # Test_type=data_driven_tests will use the tests defined
            # in apf_testsuites, apf_tests_v
            #
            if ($is_resumed_req == 0)
            {
                my $testrun_id    = $params->{testrun_id} || "";
                my $testflow_id   = $params->{testflow_id} || "";
                my $testflow_name = $params->{TESTFLOW_NAME} || "";

                $rc = $it->run_install($test_type, $testrun_id,
                                       $testflow_id, $testflow_name);

                if($rc == 5)
                {
                  $log_fh->print("Returning since rc is $rc \n");
                  return;
                }

                $self->{emcc_tag} = "APF-EMCC-SQL-INSTALLTEST-SUCCESS"
                    if ($self->{emcc_installtest} &&
                        $it->{has_postinstall_sql});

                my $use_ems_template = $params->{use_ems_template} || "yes";

                my $run_ems_installtest = ($use_ems_template eq "yes") ? 1 : 0;

                if (($is_resumed_req == 1) ||
                    (($rc == 0) && ($self->{emcc_installtest})))
                {
                    $self->{emcc_tag} = $self->_get_emcc_tag($it);
                    if ($run_ems_installtest)
                    {
                        # If EM tests fail run the EMS install test
                        $rc = $it->check_if_rerunnable();
                        $log_fh->print_header("EMS Install test");
                        $rc = $it->run_install();
                    }

                    $it->{status} = $rc;
                    $it->{sql_auto_release} = 0 if (!$rc);
                }
            }
        };

        if ($@)
        {
            #
            # As part of fix for 16028256
            #
            $die_err_msg = $@;

            if (ref($@) eq "HASH")
            {
                $die_err_msg = $@->{error_message} if ($@->{error_message});
                $self->{failed_task_obj} = $@->{task_obj} if ($@->{task_obj});
            }

            $self->{emcc_tag} = $self->_get_emcc_tag($it);
            $it->{sql_auto_release} = 0;

            $log_fh->print("SQL Files:\t$it->{sql_files}, " .
                           "Tag:\t$self->{emcc_tag}, " .
                           "PostInstallSql:\t$it->{has_postinstall_sql}, " .
                           "Err=$die_err_msg\n");

            $log_fh->print("From run_install API: " . $die_err_msg . "\n");
        }

        if($rc == 5)
        {
          $log_fh->print("Returning back since rc is $rc \n");
          return;
        }

        $it->free_throttle_resource($it->{request_id},
                                    ISD::Const::isd_request_stat_succ);

        if ($die_err_msg =~ /Patch has been manually uploaded/)
        {
            die $die_err_msg;
        }
        elsif ($die_err_msg =~ /Connection timed out/)
        {
            my $aru_obj = new ARU::BugfixRequest($self->{bugfix_request_id});
            $aru_obj->get_details();
            $params->{start_time} = $aru_obj->{requested_date};
            $params->{action}='test';
            $self->_handle_timeout($params);
        }

        my $enable_tstfwk = PB::Config::enable_tstfwk;
        my $tstfwk_products = PB::Config::tstfwk_enabled_products;
        my $tstfwk_releases = PB::Config::tstfwk_enabled_releases;
        my $tstfwk_platforms = PB::Config::tstfwk_enabled_platforms;

        my $product_id = $it->{aru_obj}->{product_id};
        my $platform_id = $it->{aru_obj}->{platform_id};

        if ($enable_tstfwk == 1)
        {
            if (grep(/^$product_id$/, @$tstfwk_products))
            {
                if (grep(/^$release_id$/, @$tstfwk_releases))
                {
                   if (grep(/^$platform_id$/, @$tstfwk_platforms))
                   {
                       $log_fh->print("test patch through new TestFramework " .
                                      "flows\n");
                       $rc_tstfwk = $it->run_tstfwk();
                   }
                }
            }
        }
    }

    my $release = $it->{aru_obj}->{release};

    $die_err_msg ||= " See log files for more information.";

    #
    # Padding the version.
    #
    my $version = APF::PBuild::Util::get_version($release);

    $log_fh->print("Value of sql_files = $it->{sql_files}\n");

    my $base_bug = $it->{aru_obj}->{bug};

    my ($bug_portid, $bug_gen_or_port, $bug_prod_id, $bug_category)
        = ARUDB::single_row_query("GET_BUG_INFO",
                                  $aru_obj->{bug});
    #
    # check if it is a clusterware patch
    #
    $it->{isPCW} = $it->is_clusterware_patch($bug_category,
                                             $version,
                                             $bug_prod_id);

    $it->{sql_auto_release} = 1
           if (($it->{sql_files} == 1) && ($it->{isPCW} == 1));
    # Intentionally leaving these additional debug statements to help
    # the verification process during testing. Can be removed after few months
    $log_fh->print("CHECK IF MANUALLY UPLOADED OR NOT 2 - $params->{aru_no} \n");

    my ($manually_uploaded) = ARUDB::single_row_query('GET_MANUAL_UPLOAD_DETAILS',$params->{aru_no}, ARU::Const::upload_requested);

    $self->{is_a_cloud_patch} = 0;

    # Get the cloud property set on the transaction
    my ($cloud_prop_set) = ARUDB::exec_sf('aru_ade_api.get_txn_property',
                                  $params->{TXN_NAME},
                                  APF::Const::cloud_patch_property, ['boolean', 0]);

    $self->{is_a_cloud_patch} = 1 if ($cloud_prop_set =~ /ver_update,\s*cloud_on/i);
    $log_fh->print("Cloud patch prop value $self->{is_a_cloud_patch} \n");

    $log_fh->print("MK files value before PCW and manual upload check $it->{mk_files} \n");
    $log_fh->print("Manually uploaded value: $manually_uploaded \n");
    $log_fh->print("PCW value: $it->{isPCW} \n");
    $it->{mk_files} = 0 if ($it->{isPCW} == 1 || (defined ($manually_uploaded) && $manually_uploaded == 1) || $self->{is_a_cloud_patch} == 1);

    $it->{spc_sql_files} = 0 if ($it->{isPCW} == 1 || (defined ($manually_uploaded) && $manually_uploaded == 1));
    $log_fh->print("MK files value after PCW and manual upload check $it->{mk_files} \n");

    my ($readme_review_products);

    eval {
        ($readme_review_products) = ARUDB::single_row_query("GET_COMPAT_PARAM",
                                                  "README_REVIEW_PRODUCTS");
    };

    #$log_fh->print("DEBUG_BLANK_README:  REVIEW_PRODUCTS: $readme_review_products\n");
    #$log_fh->print("DEBUG_BLANK_README:  PRODUCT_ID: $it->{aru_obj}->{product_id}\n");
    if ((defined ($readme_review_products)) && $readme_review_products ne "") {
        if ($it->{aru_obj}->{product_id} !~ /^$readme_review_products$/) {
            $log_fh->print("DEBUG_BLANK_README:  NOT MATCHED\n");
            $it->{blank_readme_html} = 0;
            $it->{blank_readme_txt}  = 0;
        }
    }
    #$it->{blank_readme_html} = 0 if ($it->{isPCW} != 1);
    $it->{isPCWStop} = 0;

    if ($it->{isPCW} == 1 && $version =~ /^(12\.|18\.)/) {
        $it->{isPCWStop} = 1;
    }
    $it->{isPCWStop} = 0 if ((defined ($manually_uploaded)) && $manually_uploaded == 1);
    # Disabling the clusterware patch review for all patches
    $it->{isPCWStop} = 0;

    if ((($it->{sql_files}    == 1) &&
         ($it->{sql_auto_release} == 0))
        || ( $it->is_security_one_off($base_bug) eq 'Y' &&
             !$it->is_rdbms($it->{aru_obj}->{bug}) )
        || $it->{genstubs} == 1
        || $it->{mk_files} == 1
        || $it->{blank_readme_html} == 1
        || $it->{blank_readme_txt} == 1
        || $it->{spc_sql_files} == 1)
    {
        my ($msg, $bug_txt);
        my $test_name="APF";

        my $rtn_str = "Failed"
            if ($die_err_msg !~ /submitted for Install Test|Test completed/);

        if ($rc == 0)
        {
            $msg = "Install Test $rtn_str: $die_err_msg ";
        }
        else
        {
            $msg = "Automated install tests submitted and completed ".
                "[request id = $request_id].\n";
        }

        $msg = "This is a security one off, " .
               "verify manually and release the patch.\n"
                   if ($it->is_security_one_off($base_bug) eq 'Y' &&
                        !$it->is_rdbms($it->{aru_obj}->{bug}));

        $msg = $it->{spc_sql_files_msg} . "\n"
                   if ($it->{spc_sql_files} == 1); 

        #
        # Strip if it exceeds 240 chars.
        #
        my $msg240 = Debug::get_die_msg(240, $msg);

        $log_fh->print("ARU: $aru_no , Status: internal ==\n");

        ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                       ARU::Const::patch_ftped_internal,
                       "", ARU::Const::apf2_userid, $msg240);

        #
        # The DTE install test flow duplicates this logic later
        # so for now we'll only carry forward if the return code
        # is 1 (successful EMS/legacy install test).
        #
        if ($rc == 1)
        {
            sleep(2);

            my $link = "http://" . APF::Config::url_host_port .
                "/ARU/ViewPatchRequest/process_form?aru=$aru_no";

            my ($bug_txt ,$test_name) = $it->install_test_bug_upg
                ($link,$msg,$version,$base_bug);

            my $tag_name = $test_name;
            $tag_name = "$self->{emcc_tag} $test_name"
                                   if ($self->{emcc_installtest});

            unless ($die_err_msg =~ /submitted for Install Test. APF/)
            {
                #
                # Update the bugdb.
                #
                $self->_update_bug($pse, {status        => 52,
                                          programmer    => 'PATCHQ',
                                          test_name     => $test_name,
                                          tag_name      => $tag_name,
                                          body          => $bug_txt });
            }

            my ($patch_type) = ARUDB::single_row_query('GET_PATCH_TYPE',
                                                       $aru_no) if ($aru_no);

            if ($patch_type ==  ARU::Const::ptype_cumulative_build)
            {
                my $url_host_port = APF::Config::url_host_port;
                my $port;
                ($url_host_port, $port) = split(':',$url_host_port)
                    if (ConfigLoader::runtime("production"));

                my $status_link = "http://" . $url_host_port .
                    "/ARU/BuildStatus/process_form?rid=$request_id";
                my $request_id_link = "<a href=\"$status_link\">$request_id</a>";
                my ($product_name) = ARUDB::single_row_query('GET_PRODUCT_NAME',
                                                 $it->{aru_obj}->{product_id});
                my $sub_details = "$base_bug tracking bug on $it->{aru_obj}->{platform_id} port for";

                my $mail_options = {
                'log_fh'        => $self->{log_fh},
                'product_id'    => $it->{aru_obj}->{product_id},
                'release_id'    => $it->{aru_obj}->{release_id},
                'version'       => $version,
                'product_name'  => $product_name,
                'subject'       => "APF Installtest completed for $sub_details",
                'comments'      => "has completed but assigned the patch for manual review",
                'platform'      => $it->{aru_obj}->{platform_id},
                'bug'           => $base_bug,
                'request_url'   => $request_id_link,
                'request_log'   => $request_id_link,
                'request_id'    => $request_id,
                                   };
                APF::PBuild::Util::send_bp_email_alerts($mail_options);
            }

            $it->is_system_subpatch();
            return;
        }
    }

    #
    # Check the status
    #
    my $is_system_patch = 0;  #DISABLE_SYSTEM_PATCH
    eval {
       $is_system_patch =   ARUDB::exec_sf_boolean('apf_system_patch_detail.is_system_patch_series_trk_bug',
                            $it->{aru_obj}->{bug});
    };
    if ($@)
    {
        $is_system_patch = 0;
    }

    if ($rc == 1)
    {
        $log_fh->print("Install test succeeded for $pse and " .
                       "for version $version \n");
        $log_fh->print("Calling check_install_test_farm_status API: " .
                       "$pse, $it, $aru_no, $version \n");


        my ($patch_type) = ARUDB::single_row_query('GET_PATCH_TYPE',
                                                   $aru_no) if ($aru_no);

        if ($patch_type ==  ARU::Const::ptype_cumulative_build)
        {
            my $url_host_port = APF::Config::url_host_port;
            my $port;
            ($url_host_port, $port) = split(':',$url_host_port)
                if (ConfigLoader::runtime("production"));

            my $status_link = "http://" . $url_host_port .
                "/ARU/BuildStatus/process_form?rid=$request_id";
            my $request_id_link = "<a href=\"$status_link\">$request_id</a>";
            my ($product_name) = ARUDB::single_row_query('GET_PRODUCT_NAME',
                                                         $it->{aru_obj}->{product_id});
            my $sub_details = "$base_bug tracking bug on $it->{aru_obj}->{platform_id} port for";

            my $mail_options = {
                'log_fh'        => $self->{log_fh},
                'product_id'    => $it->{aru_obj}->{product_id},
                'release_id'    => $it->{aru_obj}->{release_id},
                'version'       => $version,
                'product_name'  => $product_name,
                'subject'       => "APF Installtest completed for $sub_details",
                'comments'      => "has completed",
                'platform'      => $it->{aru_obj}->{platform_id},
                'bug'           => $base_bug,
                'request_url'   => $request_id_link,
                'request_log'   => $request_id_link,
                'request_id'    => $request_id,
                                   };
            APF::PBuild::Util::send_bp_email_alerts($mail_options);
        }

        $it->is_system_subpatch();
        $self->check_install_test_farm_status($pse,$it,$aru_no,$version);

    }
    elsif ($rc == 0)
    {
        $self->{failed_task_obj} = $it;

        my $rtn_str = "Failed"
            if ($die_err_msg !~ /submitted for Install Test/);

        my $msg = "Install Test $rtn_str: $die_err_msg";
        my $bug_body = $msg;

        if ($die_err_msg =~ /Install Test Error:/i)
        {
          $msg = $die_err_msg;
          $bug_body = $it->{die_message} if ($it->{die_message});
          $bug_body .= "\nEMS Template: " .
                       $it->{template_name} if ($it->{template_name});
          $bug_body .= "\nHost: " .
                       $it->{wkr_host} if ($it->{wkr_host});
          $bug_body .= "\nEMS Request Log: " .
                       $it->{ems_request_url} if ($it->{ems_request_url});
        }

        my $aru_prod_id = $it->{aru_obj}->{product_id};


        if ($is_system_patch == 1) {
            if ((defined($it->{req_params}->{tab_test_type})) &&
                 $it->{req_params}->{tab_test_type} eq "B") {
                 $self->{aru_orig_status} = ARU::Const::patch_ftped_internal;
                 $bug_body = 'system patch and TAB(Basic) Installtest submission failed';
                 $msg      = $bug_body;
            }
            else {
                 $bug_body = 'TAB(Comprehensive) Installtest submission failed';
                 $msg      = $bug_body;
            }
        }
        $log_fh->print("BUG Body: $bug_body\n");
        $log_fh->print("$msg\n");
        chomp ($msg);
        $it->update_system_patch()
              if (defined $it->{testmanual} && $it->{testmanual} == 1);
        #
        # Patch failed to apply.
        #
        my $aru_status = ($self->{aru_orig_status})?
                          $self->{aru_orig_status}:
                          ARU::Const::patch_ftped_internal;

        $log_fh->print("ARU: $aru_no, Status: $aru_status .\n");

        #
        # Strip if it exceeds 240 chars.
        #
        my $msg240 = Debug::get_die_msg(240, $msg);

        $log_fh->print("==> Truncated Message: $msg240, $aru_status \n");

        ARUDB::exec_sp("aru_request.update_aru",
                       $aru_no,
                       $aru_status,
                       "",
                       ARU::Const::apf2_userid,
                       $msg240);

        my $platform_id = $it->{aru_obj}->{platform_id};

        ARUDB::exec_sp('bugdb.async_create_bug_text',
                       $pse,
                       $bug_body) if ($pse);

        #
        # for em12c after submitting job, there should be
        # polling of install test job_id, this procedure should
        # not die
        # for apf bug 16870048
        #
        if (($aru_prod_id == ARU::Const::product_emgrid ||
             $aru_prod_id == ARU::Const::product_iagent  ||
             $aru_prod_id == APF::Const::product_id_emdb ||
             $aru_prod_id == APF::Const::product_id_emas ||
             $aru_prod_id == APF::Const::product_id_emfa ||
             $aru_prod_id == APF::Const::product_id_emmos))
        {
            $log_fh->print("EM Update Bug: $pse, $msg, status: 11 " .
                           "return status: $rtn_str \n");

            if ($rtn_str =~ /Failed/i)
            {
                die($msg) if ($msg);
            }
            else
            {
                $self->_update_bug($pse,
                               {status     => 11,
                                programmer => 'PBUILD',
                                test_name  => 'APF-IN-FARM-REGRESSION',
                                body => $msg});

                return;
            }
        }
        else
        {
            die($msg) if ($msg);
        }
    }
    elsif ($rc == 2)
    {
        my $msg = "DTE install test initialized in the server farm " .
            "[request id = $request_id].";

        $log_fh->print("$msg\n");
        $log_fh->print("ARU: $aru_no, Status: internal ..\n");
        $it->update_system_patch() if (defined $it->{testmanual} && $it->{testmanual} == 1);
        #
        # DTE Install test kicked off to run in serverfarm.
        #
        ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                       ARU::Const::patch_ftped_internal,
                       "", ARU::Const::apf2_userid, $msg);
    }
    elsif ($rc == 3)
    {
        #
        # In these cases neither DTE nor EMS templates are available.
        # Therefore give a message that SE team would test this manually.
        # The patch should show to be built successfully.
        #
        # We do not need to parse the fixed version in such case because the
        # request is not fully automated.
        #
        $self->{aru_obj} = $it->{aru_obj};
        $self->install_test_updates($log_fh, $aru_no, '', $pse);
        $it->update_system_patch() if (defined $it->{testmanual} && $it->{testmanual} == 1);
        my $msg_no_test = "";
        eval
        {
            my $tself = {};
            $tself->{log_fh} = $log_fh;
            if (APF::PBuild::Base::is_rdbms($tself, $pse))
            {
                $msg_no_test = "No DTE or automated test available for " .
                               "this product at present. " .
                               "Patch to be tested manually.";
            }
        };
        die $msg_no_test if ($msg_no_test);
    }
    if ($rc_tstfwk > 0)
    {
        my $msg = "install test initialized in the new TestFramework " .
                  "[request id = $request_id].";
        $log_fh->print("$msg \n");
    }
}

#
# To invoke the WLS Image Tool to generate patch images for Docker/K8S
#
sub _create_patch_image
{
    my ($self, $params) = @_;

    my $log_fh = $self->{aru_log};
    my $acr = APF::PBuild::CloudRequest->new($log_fh, $params);
    $acr->patch_image();
}

sub _upload_patch_image
{
    my ($self, $params) = @_;
 
    my $log_fh = $self->{aru_log};
    my $acr = APF::PBuild::CloudRequest->new($log_fh, $params);
    $acr->upload_patch_image();
}


#
# To submit an event to the pipeline to generate patch PCA template
#
sub _create_patch_pca_template
{
    my ($self, $params) = @_;

    my $log_fh = $self->{aru_log};
    my $acr = APF::PBuild::CloudRequest->new($log_fh, $params);
    $acr->patch_pca_template();
}

sub _upload_patch_pca_template
{
    my ($self, $params) = @_;
 
    my $log_fh = $self->{aru_log};
    my $acr = APF::PBuild::CloudRequest->new($log_fh, $params);
    $acr->upload_patch_pca_template();
}


#
# This API directly uploads the patch from the workarea. User can
# create patch in his local env and put that patch in
# workarea. Calling this API will push the patch to repository.
#
sub _upload
{
    my ($self, $params) = @_;

    die("Use 'uploadcli' for uploading a patch into ARU System. \n" .
       "See this doc for information: " .
       "http://aru.us.oracle.com:8080/help/Upload/UploadCLI.html");
}

#
# Handle die msg and send a mail alert
#
sub _handle_failure
{
    my ($self, $bugfix_request_id, $preprocess, $err_msg, $pse,$autoport) = @_;

    my $product_family;
    my $log_fh = $self->{log_fh} =  $self->{log_fh} ||$self->{aru_log};


#
##To disable bug update for GIT based backports processed from python standalone module
#

    my ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,$category, $sub_component) =
            $preprocess->get_bug_details_from_bugdb($pse);

    eval {
         $self->initialize_git_src_ctrl_type($pse);
    };

    $self->{log_fh}->print("Source control type of this release $self->{utility_version} is $self->{src_ctrl_type}\n");

    return if( $self->{src_ctrl_type} =~ /git/i );
    return if( $err_msg =~ /Patch has been manually uploaded/ ) ;
    return if( $err_msg =~ /SQL validation through mergereq/ ) ;
    $self->{log_fh} =  $self->{log_fh} ||$self->{aru_log};

    $err_msg = "Error occurred while processing this request,".
               " check the log files for more information."
            unless($err_msg);

    $self->{handle_failure} = 1;

    $self->{emcc_tag} = "" if (not exists $self->{emcc_tag});
    #
    # Extract first 240 characters
    #
    $err_msg =~ s/\s+/ /g;
    $err_msg =~ s/^\s+|\s+$//g;

    $err_msg =~ s/\n/    /g;

    return if ($err_msg =~ / is not a valid bug user/);

    my $ori_error = "$err_msg";

    $err_msg = substr($err_msg, 0, 240);
    $err_msg = "ERROR: $err_msg ..."
        unless ($err_msg =~ /ERROR/i);
    my $aru_rel_id;

    my ($aru_or_pse, $method);

    my $user_id = $self->{params}->{user_id} || "";

    my $aru_obj;
    my $status;

    $log_fh->print("User ID: $user_id \n");


    if ($bugfix_request_id || $self->{bugfix_request_id})
    {
        $bugfix_request_id = $bugfix_request_id || $self->{bugfix_request_id};

        chomp($bugfix_request_id);

        if (defined $preprocess->{aru_obj}->{aru})
        {
            $self->{aru_obj} = $preprocess->{aru_obj};
            $aru_obj = $preprocess->{aru_obj};
        }
        else
        {
            $aru_obj = ARU::BugfixRequest->new($bugfix_request_id);
            $aru_obj->get_details();
            $self->{aru_obj} = $aru_obj;
        }

        $log_fh->print("Status: $aru_obj->{status_id} \n");
        $log_fh->print("Orig Status: $self->{aru_orig_status} \n");

        $status = ($aru_obj->{status_id} == ARU::Const::patch_ftped_internal)?
                            ARU::Const::patch_ftped_internal :
                            ARU::Const::patch_code_pull_failure;

        my $aru_status = ($self->{aru_orig_status})?
                          $self->{aru_orig_status}:$status;

        $log_fh->print("Updating status of $bugfix_request_id to " .
                       "$aru_status \n");

        #
        # When we invoke the following plsql procedure update_aru, we will
        # send an ARU alert to the user; we used to set method to
        # "pb_patch_failure" and call "pbuild.send_alert" procedure to send
        # a duplicate alert. We now no longer use the method pb_patch_failure
        # so as to avoid the duplicate alerts to users.
        #
        $log_fh->print("$aru_obj->{release}, $aru_obj->{product_id}\n");
        #Hack Hack not release patch for OAS 5.5
        $aru_status = ARU::Const::patch_ftped_internal
           if($aru_obj->{release} =~  /^5\.5/ && 
              $self->{aru_orig_status} &&
              $self->{aru_orig_status} == ARU::Const::patch_ftped_internal &&
              $aru_obj->{product_id} == 14667);
        $log_fh->print("ARU: $bugfix_request_id, Status: $aru_status -\n");
        ARUDB::exec_sp('apf_queue.update_aru',
                       $bugfix_request_id, $aru_status, $err_msg); 

        if ($aru_obj->{release_id} =~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/ &&
            $aru_obj->{language_id} != ARU::Const::language_US &&
            $status == ARU::Const::patch_code_pull_failure &&
            ConfigLoader::runtime("production"))
        {
            my $user = APF::Config::transient_user;
            my $host = APF::Config::transient_host;

            my $host_list;
            my $param_key = "TRANSIENT_HOST";
        
            eval {
              ($host_list)  =  ARUDB::exec_sf('aru_parameter.get_parameter_value',
                                                    $param_key);
            };
            $host_list = $host if (!$host_list); 
    
            my $base_work = PB::Config::apf_base_work;
            my $ssh_cache_dir = dirname($base_work) .  "/.ssh_pool_cache";

            my ($ssh, $ssh_host, $ssh_lock_file) = 
                 APF::PBuild::Util::get_ssh_obj_from_pool($aru_obj,
                                      $preprocess->{system}, $log_fh,
                                      $host_list, $user, $ssh_cache_dir);

            $host = $ssh_host;
            die  "$host - SSH Connection Failed" unless ($ssh);

            my $apf_base_us_work = APF::Config::apf_base_us_work . "/" .
                                   $self->{request_id};
            $ssh->do_mkdir("$apf_base_us_work");
            $ssh->do_upload(user => $user,
                            host => $host,
                            local_file  => "$self->{aru_dir}/log",
                            remote_file => "$apf_base_us_work",
                            docmd_options => { timeout => 1200,
                                               keep_output => 'YES' } );
        }

        #
        # Bug 12610127 - Do not update the bug for Fusion NLS patch failures
        #
        return if ($aru_obj->{language_id} != ARU::Const::language_US &&
                   $status == ARU::Const::patch_code_pull_failure);

        $aru_or_pse = $bugfix_request_id;

        ($pse) = ARUDB::single_row_query("GET_PSE_BUG_NO", $bugfix_request_id)
            unless ($pse);

        $log_fh->print("[Inside this identified loop]");
        $log_fh->print("[handle_failure] PSE: $pse \n");
    }
    else
    {
        $aru_or_pse = $pse || "";
        $method     = "pb_pse_failure";
    }

    my $fusionapps_req =
              (($aru_obj->{release_id} =~
                   /^${\ARU::Const::applications_fusion_rel_exp}\d+$/) ||
               (-e "$self->{aru_dir}/log/fusionapps_error.log")) ? 1 : 0;

    #
    # check if it is a bundle patch request
    #
    my $aru_no = $bugfix_request_id || $self->{bugfix_request_id};

    my ($patch_type) = ARUDB::single_row_query('GET_PATCH_TYPE',
                                               $aru_no) if ($aru_no);

    $self->{patch_type} = $patch_type;

    if ((defined($self->{bundlepatch}) && $self->{bundlepatch}->{bpr}) ||
        ($self->{patch_type} == ARU::Const::ptype_cumulative_build))
    {
        #
        # Get max retry count for this error code and also the current count.
        # Need to call _get_test_name to retrieve the error details.
        #
        my $testname = $self->_get_test_name($aru_obj, $err_msg);
        $log_fh->print("Failed Task Obj var:\n" .
                       Dumper($self->{failed_task_obj}) . "\n")
            if (ConfigLoader::runtime("development"));

        my $is_retry =
            $self->{failed_task_obj}->{failure}->{details}->
            {error_code_props}->{retry};
        $is_retry ||= 'no';

        my $send_alert =  $self->{failed_task_obj}->{failure}->{details}->{error_code_props}->{alert} || 'yes';

        my $max_retry_count =
            $self->{failed_task_obj}->{failure}->{details}->
            {error_code_props}->{max_retries};
        my $cur_retry_count = $self->{params}->{req_retry_count};

        #
        # Reset them if they are not defined.
        #
        $max_retry_count ||= 3;
        $cur_retry_count ||= 0;

        #
        # By default, all failure types are soft.
        #
        my $failure_type =
            $self->{failed_task_obj}->{failure}->{details}->
                {error_code_props}->{type};
        $failure_type ||= 'Soft';

        $log_fh->print("Failure Type    : $failure_type\n");
        $log_fh->print("Retry On        : $is_retry\n");
        $log_fh->print("Max retry count : $max_retry_count\n");
        $log_fh->print("Cur retry count : $cur_retry_count\n");

        $log_fh->print("Inside bundlepatch if check\n");
        $pse ||= $self->{params}->{bug};

        my ($att_name, $att_value, @rest) =
            ARUDB::single_row_query('GET_CD_PATCH_DETAILS', $pse, 'STATUS_LOG');
        my $status_log = $att_value;

        #
        # Check whether request is a CD or PF for easier use later.
        #
        my $status_fh;
        my $is_cd = 0;
        if (($status_log) and ($status_log ne ''))
        {
            $is_cd = 1;
            $log_fh->print("Updating status log: $att_value\n");
            $status_fh  = new FileHandle(">> $status_log");
            $status_fh->autoflush(1);
            my $date = `date`;
            chomp($date);
            $status_fh->print("[$date] inside handle failure\n");
            #
            # By default reset the timer reset for non-hard failures.
            #
            $status_fh->print("[$date] Timer_Reset\n")
                if ($failure_type !~ /hard/i);
        }

        my ($eh, $eh_options, $mail_options, $body_msg);

        $body_msg = "\n" .
            "Bundle Patch Creation failed with $ori_error\n";

        if ($bugfix_request_id ne '')
        {
            $aru_obj->{output_column} = 'Comments';
            $aru_obj->{qa_output} = $err_msg
                if (not defined $aru_obj->{qa_output});
            $eh_options = { aru_obj       => $aru_obj,
                            product_id    => $aru_obj->{product_id},
                            bugfix_req_id => $bugfix_request_id,
                            pse           => $pse,
                            failure_type  => $failure_type,
                            attempt       => $cur_retry_count,
                            status_log    => $status_log,
                            request_id    => $self->{request_id},
                            log_fh        => $log_fh };

            $eh = APF::PBuild::ErrorHandle->new($eh_options);
        }
        else
        {
            my $request_stage = 'at patch packaging';
            $log_fh->print("Error msg: $err_msg\n");
            my $platform = ARUDB::exec_sf
                ("aru_platform.find_platform_short_name",
                  $preprocess->{platform_id});

            $request_stage = 'with label access issue'
                if ($err_msg =~ /ADE label not accessible|Could not find server/i);

            $request_stage .= " for $preprocess->{base_bug} tracking bug on $platform port";

            my $def_subject  = "APF Patch Creation failed $request_stage for";
            my $def_comments = "has failed";

            if ($failure_type =~ /Norm/i)
            {
                $def_subject = "APF Patch Creation completed for";
                my $def_comments = "has completed";
                $err_msg = $ori_error;
                $err_msg =~ s/.*: //g;
            }

            my ($product_name) = ARUDB::single_row_query('GET_PRODUCT_NAME',
                                                 $preprocess->{product_id});
            my @qa_output = ($err_msg);
            my $aru_platform_id = $preprocess->{platform_id};
            $aru_platform_id = 2000 if ($aru_platform_id =~ /289/);
            my $platform = ARUDB::exec_sf
                ("aru_platform.find_platform_short_name", $aru_platform_id);

            my $ci_txn;
            if ($is_cd)
            {
                my ($att_name, $att_value, @rest) =
                    ARUDB::single_row_query('GET_CD_PATCH_DETAILS',
                                            $pse, 'CI_TXN');
                $ci_txn = $att_value;
            }

            my $url_host_port = APF::Config::url_host_port;
            my $port;
            ($url_host_port, $port) = split(':',$url_host_port)
                if (ConfigLoader::runtime("production"));

            my $request_id = $self->{request_id};
            my $status_link = "http://" . $url_host_port .
                "/ARU/BuildStatus/process_form?rid=$request_id";
            my $request_id_link = "<a href=\"$status_link\">$request_id</a>";

            $mail_options = {
                'log_fh'        => $self->{log_fh},
                'product_id'    => $preprocess->{product_id},
                'release_id'    => $preprocess->{release_id},
                'version'       => $preprocess->{version},
                'product_name'  => $product_name,
                'subject'       => $def_subject,
                'comments'      => $def_comments,
                'qa_output'     => \@qa_output,
                'output_column' => 'Comments',
                'platform'      => $platform,
                'bug'           => $preprocess->{base_bug},
                'label'         => $preprocess->{LABEL},
                'cd_ci_txn'     => $ci_txn,
                'request_url'   => $request_id_link,
                'request_log'   => $request_id_link,
                'failure_type'  => $failure_type,
                'attempt'       => $cur_retry_count,
                'status_log'    => $status_log,
                'request_id'    => $self->{request_id},
              };
        }

        #
        # If max retries is reached or retry is not enabled, report the failure.
        #
        if (($cur_retry_count >= $max_retry_count) or ($is_retry =~ /no/))
        {
            #
            # failure_type should not be set to soft as max retries are reached.
            # For soft failures, the notifications are sent internally
            #
            #
            $mail_options->{failure_type} = ""
                if ($mail_options->{failure_type} =~ /Soft/i);
            $log_fh->print("Resetting the failure_type from soft to null\n");

            if ($is_cd)
            {
                #
                # Check for the request status
                #
                ($att_name, $att_value, @rest) =

                    ARUDB::single_row_query('GET_CD_PATCH_DETAILS',
                                            $pse,
                                            'REQUEST_STATUS');

                $log_fh->print("Request status is $att_value\n");

                if ($att_value)
                {
                    my $request_id = $self->{request}->{id} ||
                    $self->{params}->{request_id};

                    my $bp = APF::PBuild::BundlePatch->new(
                                               {request_id => $request_id,
                                                log_fh => $log_fh,
                                                bug => $pse});

                    my $date = `date`;
                    chomp($date);

                    #
                    # Get the last status
                    #
                    if ($att_value eq "PACKAGE" &&
                        (!($err_msg =~
                           /Can't use an undefined value as an ARRAY ref/)))
                    {
                        if ($failure_type =~ /hard/i)
                        {
                            $status_fh->print("[$date] Patch_Failed\n");
                            $status_fh->print
                                ("<ERROR>\nBundle Patch Creation failed ".
                                 "with $ori_error\n</ERROR>\n");

                            $bp->update_jira_key_issue($pse, '',
                                                   'Patch packaging failed',
                                                   $ori_error);
                        }
                        else
                        {
                            $body_msg = "\n" .
                              "Bundle Patch Creation failed with $ori_error\n";
                        }
                    }
                    elsif ($att_value eq "INSTALL_TEST")
                    {
                        if ($failure_type =~ /hard/i)
                        {
                            $status_fh->print("[$date] Install_Test_failed\n");
                            $status_fh->print
                                ("<ERROR>\nInstall Test failed " .
                                 "with $ori_error\n</ERROR>\n");

                            $bp->update_jira_key_issue($pse, '',
                                                   'Install Test failed',
                                                   $ori_error);
                        }
                        else
                        {
                            $body_msg = "\n" .
                              "Install Test failed with $ori_error\n";
                        }
                    }
                    elsif ($att_value eq "QA_TEST")
                    {
                        if ($failure_type =~ /hard/i)
                        {
                            $status_fh->print("[$date] QA_failed\n");
                            $status_fh->print
                                ("<ERROR>\nProduct QA tests failed ".
                                 "with $ori_error\n</ERROR>\n");

                            $bp->update_jira_key_issue($pse, '',
                                                   'Product QA Test failed',
                                                   $ori_error);
                        }
                        else
                        {
                            $body_msg = "\n" .
                              "Product QA tests failed with $ori_error\n";
                        }
                    }
                }

                #
                # enable cd serialization if the flag is set
                #
                my ($param_value) =
                ARUDB::single_row_query("GET_ARU_PARAM",
                                        'ENABLE_CD_QUEUE');

                if ($param_value == 1 && ($failure_type =~ /hard/i))
                {
                    #
                    # dequeue Q
                    #
                    my ($att_label, $label_value, @label_rest) =
                    ARUDB::single_row_query('GET_CD_PATCH_DETAILS',
                                            $pse, 'LABEL');

                    my ($att_ci, $ci_value, @cil_rest) =
                        ARUDB::single_row_query('GET_CD_PATCH_DETAILS',
                                                $pse, 'CI_TXN');

                    my ($type_att ,$type_value, @type_rest) =
                        ARUDB::single_row_query('GET_CD_PATCH_DETAILS',
                                                $pse, 'TYPE');

                    my $options = {
                                   'request_id' =>
                                   $self->{request}->{id} ||
                                   $self->{params}->{request_id}
                                   || $self->{request_id},
                                   'pse_bug'    => $pse,
                                   'bug'        => $pse,
                                   'label'      => $label_value,
                                   'bpr_label'  => $label_value,
                                   'bpr_type'   => $type_value,
                                   'cd_ci_txn'  => $ci_value,
                                   'log_fh'     => $log_fh,
                                  };

                    my $cdbp   = APF::PBuild::CDBundlePatch->new($options);
                    $cdbp->cd_dequeue_enqueue("failed", $pse, $ci_value);
                }

                $status_fh->close();
            }
            else  # This is a PF request.
            {
                # Nothing special here.
            }

            #
            # For all Bundle Patch requests, we need to log a P1 bug and send
            # email notifications whenever there is a failure.
            #
            my $bug_no;
            if ($bugfix_request_id ne '')
            {
                $eh->{bughash}->{body} .= $body_msg;
                $bug_no = $eh->file_p1_bug if ($failure_type !~ /Norm/i);
                $eh->set_P1_Reason_tg($bug_no);
                $eh->send_mail($bug_no);
            }
            else
            {
                APF::PBuild::Util::send_bp_email_alerts($mail_options)
                        if ($send_alert !~ /no/i);
            }

            sleep(5);
            eval
            {
                my ($bug_tag_err_msg) =
                    ARUDB::exec_sf('bugdb.create_or_append_bug_tag',
                                   $bug_no, "apf_pf");
            };
            $log_fh->print("Problem appending apf_pf tag: $@\n") if ($@);

        } # End of max retries
        else
        {
            #
            # Retry is happening. Send email notification for each retry.
            #
            if ($bugfix_request_id ne '')
            {
                $eh->send_mail();
            }
            else
            {
                APF::PBuild::Util::send_bp_email_alerts($mail_options);
            }
        }

        #
        # If the failure type is normal. It means that the failure is expected
        # and we should not show as an error. However, we still need to update
        # the PSE with the message.
        #
        if ($failure_type =~ /Norm/i)
        {
            ARUDB::exec_sp('bugdb.async_create_bug_text', $pse, $err_msg);
            $self->{die} = 0;
        }

        #
        # Update Bundle Patch failures in APF_BUNDLES table
        #
        my %bp_details = (
                             'to_label_name'        => $preprocess->{LABEL},
                             'patch_current_status' => ISD::Const::isd_request_stat_fail,
                             'remarks'              => $err_msg
                         );
        eval
        {
            my $base = APF::PBuild::Base->new(
                                     work_area  => $self->{aru_dir},
                                     request_id => $self->{request_id},
                                     aru_obj => $aru_obj|| undef,
                                     log_fh => $self->{aru_log});
            $base->update_bundle_details(\%bp_details);
        };
        if($@)
        {
            $log_fh->print("update_bundle_details API invocation part failed:$@ \n");
        }
    }

    #
    # All failures are being triaged by SE going forward.
    #

    # bug 8644620, do not change assignee if describe fails
    my $action     = $self->{action};
    my $assignee   = 'PATCHQ';
    my $testname   = 'APF-FAIL';
    my $pse_status = 52;

    my $test_name_errors = APF::Config::test_name_errors;
    #
    # putting it as a workaround
    # will remove it in the next sprint
    #
    $test_name_errors->{'APF-ADE-DESCTRANS-FAIL'} =
                       ['describetrans failed for txn'];

    my $is_autoport = 0;
    my $post_fmw12c_enabled = APF::Config::post_fmw12c_data;
    my $orch_ref;
    my $is_fmw12c_post_fail = 0;
    my $pse_num ;
    if (defined $pse && $pse ne "")
    {
        $pse_num = $pse;
    }
    else
    {
        $pse_num = $self->{params}->{bug} ||
            $self->{preprocess}->{pse};
    }

    my $pse_gen_port;
    eval {
    ($pse_gen_port) = ARUDB::single_row_query("GET_GENERIC_OR_PORT_SPECIFIC",
                                            $pse_num);
    };

    $self->{log_fh}->print("DEBUG: GEN PORT: $pse_gen_port \n");
    if ($post_fmw12c_enabled && (defined $pse_gen_port && uc($pse_gen_port) eq "O"))
    {
        $self->{log_fh}->print("DEBUG: entered into orchestration loop \n");
        my ($pse_plat_id, $pse_prod_id, $pse_rel_id,
            $pse_version);

        eval {
        if (! defined $self->{aru_obj}->{aru} ||
            $self->{aru_obj}->{aru} eq "")
        {
            if (defined $preprocess->{platform_id} &&
                defined $preprocess->{product_id} &&
                defined $preprocess->{release_id} &&
                defined $preprocess->{version})
            {
                $pse_plat_id = $preprocess->{platform_id};
                $pse_prod_id = $preprocess->{product_id};
                $pse_rel_id = $preprocess->{release_id};
                $pse_version = $preprocess->{version};
            } else
            {
                my ($base_bug, $bugdb_platform_id, $bugdb_prod_id,
                    $category, $sub_component);
                ($base_bug, $pse_version, $bugdb_platform_id, $bugdb_prod_id,
                 $category, $sub_component) =
                     $preprocess->get_bug_details_from_bugdb($pse_num,
                                                             $is_autoport);

                ($pse_plat_id) = ARUDB::single_row_query("GET_APF_PLATFORM_ID",
                                                         $bugdb_platform_id);
                my $product_abbr;
                ($pse_prod_id, $product_abbr) =
                    APF::PBuild::Util::get_aru_product_id($bugdb_prod_id,
                                                          $pse_version);
            }
        }

        my $pse_bug = $self->{params}->{bug} ||
                                             $self->{preprocess}->{pse};
        $orch_ref =
            APF::PBuild::OrchestrateAPF->new({request_id => $self->{request_id},
                                             pse    => $pse_bug,
                                             aru_obj => $self->{aru_obj},
                                             log_fh => $self->{log_fh}});

        if (! defined $self->{aru_obj}->{aru} ||
            $self->{aru_obj}->{aru} eq "")
        {
            $self->{platform_id} = $orch_ref->{platform_id} = $pse_plat_id;
            $self->{release_id} = $orch_ref->{release_id} = $pse_rel_id;
            $self->{product_id} = $orch_ref->{product_id} = $pse_prod_id;
            $self->{version} = $self->{utility_version} = $pse_version;
            $orch_ref->{version} = $orch_ref->{utility_version} =
                $pse_version;
        } else
        {
            $orch_ref->{aru_obj} = $self->{aru_obj};
            $pse_rel_id = $self->{aru_obj}->{release_id}
                if (defined $self->{aru_obj}->{release_id} &&
                    $self->{aru_obj}->{release_id} ne "");
        }

        my $is_fmw12c = $orch_ref->is_fmw12c();
        my ($aru_rel_name);

        $self->{log_fh}->print("DEBUG: Release Info: $pse_rel_id,".
                               "$is_fmw12c \n");

        if (defined $pse_rel_id && $pse_rel_id ne "")
        {
            ($aru_rel_name) =
                ARUDB::single_row_query("GET_ARU_RELEASE_NAME",
                                        $pse_rel_id);
        }

        if ($is_fmw12c)
        {
            if (defined $err_msg && $err_msg ne "")
            {
                $err_msg =~s/ERROR: //;
                $err_msg = "FMW12c Patch failed to build. ". $err_msg;
                $err_msg = substr($err_msg, 0, 240);
                $err_msg = "ERROR: $err_msg ..."
                    unless ($err_msg =~ /ERROR/i);
            }
            $is_fmw12c_post_fail = 1;
            $self->{fmw12c_skip_def_assignee} = 1 if($err_msg =~ /PVT tool/);
        }
      };
    }

    $self->{log_fh}->print("DEBUG: Error Message :$err_msg \n");
    $testname = $self->_get_test_name($aru_obj, $err_msg);

    if ($is_fmw12c_post_fail == 1)
    {
        $self->{log_fh}->print("DEBUG: FMW12c TESTNAME :$testname \n");
        my $fmw12c_retry_cnt =
            $self->{failed_task_obj}->{failure}->{details}->{error_code_props}->{max_retries};

        my ($isd_req_type_code) =
            ARUDB::single_row_query("GET_REQUEST_TYPE_CODE",
                                    $self->{request_id});

        my ($retry_req_cnt) =
            ARUDB::single_row_query("GET_RETRY_REQ_COUNT",
                                    $self->{request_id},
                                    ISD::Const::st_apf_preproc);

        $self->{log_fh}->print("DEBUG: Retry COUNT: $retry_req_cnt ,".
                               "FMW12c: $fmw12c_retry_cnt \n");

        eval {
            my $fmw12c_pse = $self->{params}->{bug} ||
                $self->{preprocess}->{pse};
            my $fmw12c_action_name = APF::Config::fmw12c_action_name;

            my $fmw12c_action = $fmw12c_action_name->{$isd_req_type_code};
            $orch_ref->post_fmw12c_data($fmw12c_pse,
                                        $fmw12c_action,
                                        $self->{request_id},
                                        undef,
                                        $err_msg,
                                        "FAILED");
     };
    }

    my $throttle_error_code = $self->{throttle_error_code};
    $self->{log_fh}->print("DEBUG: _handle_failure: ".
                           "Test Name: $testname,".
                           "Throttle Error Code: $throttle_error_code \n");

    if (defined $throttle_error_code && $throttle_error_code ne "")
    {
        $self->{log_fh}->print("DEBUG: _handle_failure: Throttle Error Code :".
                               "$throttle_error_code \n");
        my $base_ref =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                        request_id => $self->{request_id},
                                        pse    => $self->{params}->{bug} ||
                                        $self->{preprocess}->{pse},
                                        aru_obj => $self->{aru_obj},
                                        log_fh => $self->{log_fh});
        $base_ref->check_resubmit_throttled_req($throttle_error_code);
    }

    $log_fh->print("Assignee: $assignee \n");
    $log_fh->print("Test Name: $testname \n");

    #
    # find the correct test_name for the error
    #
    if ($testname =~ /APF-FAIL|UNKNOWN-ERROR|APF-UNSUPPORTED-TXN-FILE/) {
      foreach my $test_name (sort keys %$test_name_errors)
      {
          my $arr = $test_name_errors->{$test_name};

          for my $i (@$arr)
          {
              if ($err_msg =~ /$i/)
              {
                  $testname = $test_name;
                  my $files_list = $2;
                  my $inv_file = $1;

                  if ($testname =~ /APF-UNSUPPORTED-TXN-FILE/)
                  {
                      $testname .= "$inv_file";
                  }
                  elsif ($testname =~ /APF-WKR-BUILD-MERGE/)
                  {
                      $testname .= "$files_list";
                  }
                  $self->{log_fh}->print("DEBUG: TestName: $testname \n");
              }
          }
      }
    }


    #
    # Bug:16100691 Kspare validation failure
    #
    my $kspre_err_msg = $test_name_errors->{'APF-KSPRE-VALIDATION-FAILED'}->[0];

    $testname = 'APF-KSPRE-VALIDATION-FAILED'
        if $err_msg =~ /$kspre_err_msg/i;

    my ($base,$is_fmw11g, $is_injection_level,$is_fmw11g_flag);

    #
    # aru_obj will be null during preprocessing,before checkin.Hence an else
    #
    if (defined($self->{aru_obj}->{bugfix_id}))
    {
        $base =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                        request_id => $self->{request_id},
                                        pse    => $self->{params}->{bug} ||
                                        $self->{preprocess}->{pse},
                                        aru_obj => $self->{aru_obj},
                                        log_fh => $self->{log_fh});

        ($is_fmw11g, $is_injection_level) = $base->is_fmw11g();

        #
        # Below if else blk is to identify a fmw11g patch during prreprocessing
        # to make an appropriate bug update during Entry Failure:Bug 15951201
        #
        $is_fmw11g_flag = 1 if ($is_fmw11g == 1);
    }
    else
    {
        eval
        {
            #
            # same logic of sub is_fmw11g() is implemented here
            #
            my ($platform_id,$product_id, $release_id, $version);
            $self->{log_fh}->print("Check for fmw11g pse : \n");

            if ((defined($preprocess->{platform_id})) &&
                (defined($preprocess->{product_id})) &&
                (defined($preprocess->{release_id})) &&
                (defined($preprocess->{version})))
            {
                $platform_id = $preprocess->{platform_id};
                $product_id = $preprocess->{product_id};
                $release_id = $preprocess->{release_id};
                $version = $preprocess->{version};
            }
            else
            {
                if ($self->{bugfix_request_id})
                {
                    my ($patch_request) =
                        ARUDB::single_row_query("GET_PSE_BUG_NO",
                                                $self->{bugfix_request_id});

                    my ($rptno, $base_rptno, $comp_ver, $status, $version,
                        $port_id, $gen_or_port, $product_id, $category,
                        $sub_component, $customer, $version_fixed,
                        $test_name, $rptd_by)
                            = ARUDB::single_row_query("GET_BUG_DETAILS",
                                                      $pse);

                    if ((!$patch_request) && ($gen_or_port ne 'B') &&
                        ($gen_or_port ne 'M') && ($gen_or_port ne 'I') &&
                        ($gen_or_port ne 'Z'))
                    {
                        $is_autoport = 1;
                        $pse = $self->{bugfix_request_id};
                    }
                }

                #
                # fetch platform_id , product id and release id
                #
                my ($base_bug, $bugdb_platform_id, $bugdb_prod_id,
                    $category, $sub_component);
                ($base_bug, $version, $bugdb_platform_id, $bugdb_prod_id,
                 $category, $sub_component) =
                    $preprocess->get_bug_details_from_bugdb($pse, $is_autoport);

                ($platform_id) = ARUDB::single_row_query("GET_APF_PLATFORM_ID",
                                                         $bugdb_platform_id);
                my $product_abbr;
                ($product_id, $product_abbr) =
                    APF::PBuild::Util::get_aru_product_id($bugdb_prod_id,
                                                          $version);

                my @release_details =
                    $preprocess->get_release_details
                        ($pse,
                         $base_bug, $product_id, 1);

                my $cpct_release_id;
                my $is_cpct_release =
                    ARUDB::exec_sf_boolean('aru.pbuild.is_cpct_release',
                                           $pse,'', \$cpct_release_id);

                if ($is_cpct_release)
                {
                    @release_details = ARUDB::query('GET_RELEASE_INFO_CPCT',
                                                    $cpct_release_id);
                }

                my ($release_name, $rls_long_name);

                foreach my $current_release (@release_details)
                {
                    ($release_name, $release_id, $rls_long_name)
                        = @$current_release;
                    #
                    # for BPs & Psu releases, the pad_version of utility
                    # version returns the same value
                    #
                    my ($bug_version) =
                        ARUDB::single_row_query('GET_BUG_VERSION', $pse);
                    last if ($bug_version =~/BUNDLE/) &&
                            ($rls_long_name =~/BP/);
                }
            }

            $self->{platform_id} = $platform_id
                if (! $self->{platform_id});
            $self->{product_id} = $product_id
                if (! $self->{product_id});
            $self->{release_id} = $release_id
                if (! $self->{release_id});
            $self->{version} = $version
                if (! $self->{version});
            my $parent_prod_id;
            ($product_family, $parent_prod_id) =
                $preprocess->get_product_family($platform_id,
                                                $product_id,
                                                $release_id);
            $self->{log_fh}->print("product family : $product_family\n");
            $version =~ m/(\d+).(\d+).(\d+).(\d+).(\d+).*/;
            my $version_3_digits = "$1$2$3";
            my $version_5_digits = "$1$2$3$4$5";

            $is_fmw11g_flag = 1
                if ($version_3_digits >= 1111 && $product_family eq "oasp_pf");
         };

         $err_msg = 'ERROR:'.$@ if $@;
    }

    my ($product_family, $aru_fa_prod_id, $aru_fa_rel_id);
    if ($self->{aru_obj}->{product_id})
    {
        $aru_fa_prod_id = $self->{aru_obj}->{product_id};
        $aru_fa_rel_id = $self->{aru_obj}->{release_id};
    }
    else
    {
        $aru_fa_prod_id = $self->{product_id};
        $aru_fa_rel_id = $self->{release_id};
    }

    if (defined $aru_fa_rel_id &&
        $aru_fa_rel_id =~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        $log_fh->print("DEBUG: Product ID: $aru_fa_prod_id,".
                       "Release ID: $aru_fa_rel_id\n");

        my ($aru_fa_prod_abbr) = ARUDB::single_row_query('GET_PRODUCT_ABBREVIATION',
                                                         $aru_fa_prod_id);
        $log_fh->print("DEBUG: Product Abbr: $aru_fa_prod_abbr \n");

        ($product_family) = ARUDB::single_row_query(
                                            'GET_PRODUCT_FAMILY',
                                            $aru_fa_rel_id,
                                            ARU::Const::direct_relation,
                                            $aru_fa_prod_abbr);
        $product_family = uc($product_family);
    }

    $log_fh->print("DEBUG: Product Family: $product_family \n");
    my $bug;
    $bug = $pse if (defined($pse) && $pse ne '');
    $bug = $self->{params}->{bug} if (!defined($bug) || $bug eq '');

    my ($abstract, $category, $gen_or_port, $priority, $port_id, $prod_id);
    ARUDB::exec_sp("bugdb.get_bug_info",
                    $bug, \$abstract, \$category, \$gen_or_port,
                    \$priority, \$port_id, \$prod_id);

    my $bugdb_err_msg = "This request is now queued for " .
                        "manual processing. ";

    my ($is_stackpatch,$spb_label);
    $is_stackpatch=0;
    eval
    {
        ($is_stackpatch,$spb_label) = $preprocess->is_stackpatch();
    };

    if($is_stackpatch)
    {
        $log_fh->print("\n DEBUG: Stack Patch Bundle : $is_stackpatch\n");
        ARUDB::exec_sp('bugdb.async_create_bug_text', $pse,  substr($err_msg, 0, index($err_msg, " at ") || length($err_msg)));

    }
    my $is_fmw12c = 0;
    eval
    {
        $is_fmw12c = $preprocess->is_fmw12c();
    };

    if ($is_fmw12c)
    {
        if($gen_or_port eq "O")
        {
            $bugdb_err_msg .= "If this patch is urgent and requires " .
                            "immediate attention, please follow the process " .
            "documented at: https://confluence.oraclecorp.com/confluence/display/".
                        "SE/FMW12c+Patch+Creation+Guide";
        }
    }
    elsif (!(defined $self->{gen_port}))
    {
        if ($is_fmw11g_flag == 1)
        {
             $bugdb_err_msg .= "If this patch is urgent and requires " .
                        "immediate attention, please follow the process " .
                        "documented at: https://confluence.oraclecorp.com/confluence/" .
                        "display/SE/Process+to+Request+Immediate+Attention+for+a+Patch"
                   if ($gen_or_port eq 'O');
        }
        else
        {
            if ($aru_fa_rel_id =~ /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
            {
                $bugdb_err_msg .= "Requestor, please contact $product_family " .
                    "release integrator if this patch request requires urgent " .
                        "attention.";
            }
            else {
                $bugdb_err_msg .= "Requestor, please contact a Database Fixdelivery " .
                    "representative if this patch request requires urgent " .
                        "attention.\n" .
			    "Fixed Delivery Esclation process\n" .
				"(https://confluence.oraclecorp.com/confluence/display/SE/Fix+Delivery+%3A+Escalation+Process)";
            }
        }
    }
    else
    {
        my $due_to = "BugDB";
        my $change_to;
        my $gen_port = $preprocess->get_gen_port($self->{params}->{bug});

        $due_to = "ADE"
            if (($testname eq 'APF-ADE-CREATE-VIEW-ERROR') ||
                ($testname eq 'APF-ADE-FAILURE') ||
                ($testname eq 'APF-ADE-ERROR') ||
                ($testname eq 'APF-CREATE-TRANSACTION-ADE-ERROR'));

        $due_to = "host"
            if (($testname eq 'APF-HOST-ISSUES') ||
                ($testname eq 'APF-HOST-TIMEDOUT') ||
                ($testname eq 'APF-HOST-NO-SPACE-AVAILABLE'));

        $change_to = "11\/PSEREP"
            if (($gen_port eq "B") || ($gen_port eq "I") || ($gen_port eq "Z"));

        $change_to = "52\/PSEREP"
            if (($gen_port eq "M") || ($gen_port eq "O"));

        $bugdb_err_msg = "This request failed due to $due_to issue. " .
          "The request can be resubmitted to APF after verifying the logs " .
          "and by moving this bug to $change_to."
            if (($testname eq 'APF-ADE-CREATE-VIEW-ERROR') ||
                ($testname eq 'APF-ADE-FAILURE') ||
                ($testname eq 'APF-ADE-ERROR') ||
                ($testname eq 'APF-CREATE-TRANSACTION-ADE-ERROR') ||
                ($testname eq 'APF-HOST-ISSUES') ||
                ($testname eq 'APF-HOST-TIMEDOUT') ||
                ($testname eq 'APF-HOST-NO-SPACE-AVAILABLE') ||
                ($testname eq 'APF-BUGDB-ERROR'));

        my $upd_msgs = APF::Config::backport_handover_msg;
        foreach my $upd_test_name (sort keys %$upd_msgs)
        {
            if ($upd_test_name eq $testname)
            {
                $bugdb_err_msg = "Reason: " . $upd_msgs->{$upd_test_name} .
                    " Refer to the following link for details:\n" .
                    "  https://confluence.oraclecorp.com/confluence/display/SE" .
                    "/Backport+Automation+-+FAQs#BackportAutomation-FAQs-6.9)" .
                    "APFhashandedovermybackportwithoutanytxn,whatdoIneedtodo?";

                if ($upd_test_name eq "APF-KSPARE")
                {
                    $bugdb_err_msg = $bugdb_err_msg . "\n\n" .
                      "For using kspare on proactive backports, please refer " .
                      "to https://confluence.oraclecorp.com/confluence/pages" .
                      "/viewpage.action?pageId=86296334";
                }
            }
        }
    }
    #
    #  exception for jox files : Bug 9006584
    #
    if ($testname eq 'APF-JOX')
    {
        my $new_err_msg = "This request includes jox.c and/or joxoff.c.".
             " APF is currently unable to handle these files (see ".
             "Bug 9006584) requiring this patch to be handled manually.\n";

        $bugdb_err_msg = $new_err_msg.$bugdb_err_msg;
    }

    if ($testname eq 'APF-NO-DTE')
    {
      $assignee      = 'PATCHQ';
      $bugdb_err_msg = $err_msg ." " . $bugdb_err_msg;
    }
    if ($testname eq 'APF-EMS-CLONE-RETRY')
    {
        if ($aru_obj)
        {
            $self->{emcc_installtest} =
                APF::PBuild::Util::is_emcc_installtest($aru_obj);
            $self->{emcc_tag} = "APF-EMCC-INSTALLTEST-FAIL"
                if ($self->{emcc_installtest} &&
                    (not exists $self->{emcc_tag}));
        }

        $bugdb_err_msg = "EMS FlexClone Failed. ".
                         "Flexclone will be retried by APF." ;
    }

    $log_fh->print("Testname: $testname \n");

    $bugdb_err_msg = $err_msg . " " . $bugdb_err_msg
        if ($err_msg =~ /APF is already processing a request/);

    my @tmp_array = split(/ at \//,$err_msg);
    my $new_err_msg = $tmp_array[0] if ($tmp_array[0]);

    if (($err_msg =~ /Checkin Commit Failed:/ ) ||
        ($err_msg =~ /1 hop rule violation/)){

      $new_err_msg =~ s/Checkin/Check-in/i;
      $new_err_msg =~ s/ORA-20001://i;
      $new_err_msg =~ s/ Create Transaction: //i;

      $bugdb_err_msg = $new_err_msg . " " . $bugdb_err_msg
    }

    my $req_type = (defined $self->{gen_port}) ? "Merge" : "Patch";
    if ($req_type eq "Patch")
    {
        if (($self->{bugdb_prod_id} == ARU::Const::product_bugdb_beaowls) ||
            (defined $aru_obj &&
               ($aru_obj->{product_id} == APF::Const::product_id_beaowls)))
        {
            my ($def_assignee, $status) = ARUDB::single_row_query(
                                             'GET_DEFAULT_ASSIGNEE',
                                             $pse);
            $assignee   = $def_assignee;
            $pse_status = 11;
        }
    }

    my ($status_link, $notification_err_link);
    ($pse) = ARUDB::single_row_query("GET_PSE_BUG_NO", $bugfix_request_id)
        unless ($pse);

    if ($pse)
    {
        #
        # get the status log link and update in the bugdb
        #
        my ($transaction_id) =
               ARUDB::single_row_query('GET_BUILD_TRANSACTION_ID_FROM_PSE',
                                       $pse);
        $status_link = "http://" . APF::Config::url_host_port .
                       "/ARU/BuildStatus/process_form?rid=".$transaction_id;
    }

    $notification_err_link = "$req_type Request failed. Log files can be " .
        "viewed <a href=". $status_link .">here</a>. " if $status_link;

    my $pb_alert_sent = 0;
    if ($method)
    {
        ARUDB::exec_sp("pbuild.send_alert", $method, $aru_or_pse,
                   $self->{request_id}, $user_id, $err_msg . "<BR><BR>".
                   $notification_err_link);
        $pb_alert_sent = 1;
    }

    #
    # mail alert to be sent only for US Fusion Patches
    #  Discarding NLS / Platform Patches
    #  Bug 14471208
    #

    my $aru_rel_id =  $self->{aru_obj}->{release_id};
    if (! defined $aru_rel_id || $aru_rel_id eq "")
    {
        $aru_rel_id = $self->{preprocess}->{release_id}
            if ($self->{preprocess}->{release_id});
        $aru_rel_id = $preprocess->{release_id}
            if ((! $aru_rel_id) || ($preprocess->{release_id}));

        $aru_rel_id = $self->{release_id}
            if ((! $aru_rel_id) || ($self->{release_id}));
    }
    if (($aru_rel_id =~
        /^${\ARU::Const::applications_fusion_rel_exp}\d+$/) &&
        ($aru_obj->{language_id} == ARU::Const::language_US) &&
        (($aru_obj->{platform_id} == ARU::Const::platform_generic) ||
         ($aru_obj->{platform_id} == ARU::Const::platform_linux64_amd))
       )
    {
        #
        # after call to apf_queue.update_aru, aru_obj is not containing the
        # updated values. Hence had to repopulate aru_obj such that it has
        # the latest status.
        #

        $aru_obj = ARU::BugfixRequest->new($bugfix_request_id);
        $aru_obj->get_details();

        my $bundle_type  =
            ARUDB::exec_sf('aru_bugfix_attribute.get_bugfix_attribute_value',
                           $aru_obj->{bugfix_id},
                           ARU::Const::group_patch_types);

       #
       # Running fre log gather
       #

       my ($analyzer,$event_url,$event_id) ;

       eval{
       $analyzer = APF::PBuild::FABuildAnalysis->new(
                                            {'log_fh' => $self->{log_fh},
                                             'req_id' => $self->{request_id},
                                             'err_msg' => $err_msg,
                                             'aru_obj' => $self->{aru_obj} });
       ($event_url,$event_id) = $analyzer->run_FRE_log_gather();

       $self->{log_fh}->print("FRE log gather event : $event_url,$event_id \n");
       $self->{log_fh}->print("Adding event to transaction attribute \n");
       my ($err_txn_id) =
               ARUDB::exec_sf('aru.aru_transaction.get_transaction_id',
                              $aru_obj->{bugfix_id}, $aru_obj->{aru});
       ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                      $err_txn_id, 'FRE_EVENT_VIEWER', $event_url);
       };

       if($@)
       {
        $self->{log_fh}->print("FRE log gather failed : $@ \n");
       }

       if($event_url)
       {
        $base->{freloggather} = 1;
        $base->{fre_event_url} = $event_url;
        $base->{fre_event_id} = $event_id;
       }

       $base->send_fusion_alert($aru_obj,
                      'Fusion Patch Build Failure',
                      $user_id,
                      "Fusionapps patch failed to build",
                      $pse,
                      $autoport);
       $self->{log_fh}->print("Mail alert sent \n");

       $base->{freloggather} = 0;

       $self->update_skip_bugs($self->{aru_obj} , 0);

    }

    if($err_msg=~/APF does not support FusionApps one-off requests/)
    {
    $base =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                        request_id => $self->{request_id},
                                        pse    => $pse,
                                        log_fh => $self->{log_fh});
    $base->{alert_type} = "one-off-failure";
    $base->send_fusion_alert("",
                             'Fusion Patch Build Failure',,
                             $user_id,
                             "FusionApps one-off patches not supported in APF",
                             $pse,
                             $autoport,
                             $self->{request_id},
                             $err_msg);
    $self->{log_fh}->print("Mail alert sent for one-off to userid $user_id\n");
    ARUDB::exec_sp('bugdb.async_create_bug_text',
                   $pse,
                   $err_msg);

   }

    my $err_msg_tmp = $bugdb_err_msg || $err_msg;

    #
    # Update the bugdb.
    #
    # Do not update the bug when describe mode fails
    # this could lead to re-opening of the bug.
    #
    # Do not update the base bug if the autoport request fails before a
    # checkin is created.
    #
    my $tag_name = $testname;
    $tag_name = "$self->{emcc_tag} $testname";

    #
    # update bugdb test name with unsup filenames
    #
    if($testname eq "APF-UNSUPPORTED-FILES")
    {
     $testname =
         ARUDB::exec_sf("aru.aru_bugfix_attribute.get_bugfix_attribute_value",
                        $self->{aru_obj}->{bugfix_id},
                        ARU::Const::apf_unsup_files);
     if($testname)
     {
      $testname = substr( $testname, 0, 200 );
     }
     else
     {
      $testname = "APF-UNSUPPORTED-FILES";
     }
    }

    $self->{testname} = $testname;
    $self->{tag_name} = $tag_name;

    #
    # validate_assignee is 1 means got correct assignee already.
    # Allow only validate_assignee is 0
    #
    my $validated_assignee = 0;

    if (($aru_rel_id !~
            /^${\ARU::Const::applications_fusion_rel_exp}\d+$/) &&
       (($gen_or_port eq 'B' ||
         $gen_or_port eq 'I' || $gen_or_port eq 'Z')))
    {
        #
        # For Backport failures we need to send alert
        # Bug : 17036078
        #
        $method     = "pb_pse_failure";
        $aru_or_pse = $pse || "";
        ARUDB::exec_sp("pbuild.send_alert", $method, $aru_or_pse,
            $self->{request_id}, $user_id, $err_msg . "<BR><BR>".
            $notification_err_link)
            if($pb_alert_sent != 1);

        #
        # Fix for Bug:17566525
        # To update Error description for P1 BLR failures.
        #
        $self->{bugdb_err_msg} = $err_msg;

        #
        # This is required due to, on P1 BLR failure we need to send alert
        #
        $log_fh->print("\nDEBUG error msg : $err_msg\n");
        if ($err_msg =~ /The transaction (.*?) is already in closed state by (.*?) and contains the backend branched elements/)
        {
            $testname     = 'APF-INCORRECTLY-RETRIED';
        }
        $self->{log_fh}->print("\nDev assingnee : $assignee and status : $pse_status");

        my ($bug_assignee, $bug_status, $ignore_cpm) =
            $self->get_base_bug_owner($bug, $testname, $is_fmw12c, $aru_rel_id);
        
        if ($err_msg =~ /The transaction (.*?) is already in closed state by (.*?) and contains the backend branched elements/)
        {     
            $assignee     = $2; 
            $pse_status   = 35; 
            $bug_assignee = $assignee;
            $bug_status   = $pse_status;
        }

        $assignee = $bug_assignee;
        $pse_status = $bug_status;

        $self->{log_fh}->print("\n Checking for the flag farm_dev_assignment_diff_found : $preprocess->{farm_dev_assignment_diff_found}");
        if ($preprocess->{farm_dev_assignment_diff_found} == 1)
        {
            my ($assignee_id) = ARUDB::single_row_query('GET_BASE_BUG_ASSIGNEE', $bug);
            $self->{log_fh}->print("\n\nBase bug assingnee : $assignee_id");
            $assignee = $assignee_id;
            $pse_status = 11;
        }
        if ($err_msg =~ /APF does not support this backport as it is incorrectly filed - BUGDB product:(.*?), Component:(.*?), Component version:(.*?)$/)
        {
            my ($assignee_id) = ARUDB::single_row_query('GET_SUPPORT_CONTACT_NAME', $bug);
            $self->{log_fh}->print("\n\nsupport contact name  : $assignee_id");
            $bug_assignee = $assignee = $assignee_id;
            # bug : 33562222 to set the bug status as 53 [Reject status]
            $bug_status = $pse_status = 53;
            my $component = $2;
            my $version = $3;
            $err_msg_tmp = "The backport is filed incorrectly here. The component used is $component " .
                           "but the component version is $version\n";	
            $err_msg_tmp .= "a. If the BLR/CI is filed for clusterware PCW product, then component must be PCW " .
                            "and component version must be OCWRU/OCWPSU.\n";	
	    $err_msg_tmp .= "b. If the BLR/CI is filed for clusterware USM product, then component must be USM " .
                            "and component version must be ACFSRU/ACFSPSU.\n";	
            $err_msg_tmp .= "c. If the BLR/CI is filed for clusterware FPP product, then component must be FPP " .
                            "and component version must be RHPRU.\n";
            $err_msg_tmp .= "d. If the BLR/CI is filed for RDBMS product, then component must not be any of these " .
                            "component versions OCWRU|RHPRU|ACFSRU|OCWPSU|ACFSPSU .\n";
            $err_msg_tmp .= "You can update the bug to the right component and component version and then move the back port to " .
                            "11/PSEREP or you can submit using the cmd : apfcli --blr/ci/mlr <blr/ci/mlr>.\n";
            $self->{log_fh}->print("\n\nerr_msg_tmp  : $err_msg_tmp");
        } 
        $self->{log_fh}->print("\nDev assingnee : $assignee and status : $pse_status for error : $err_msg");

         
        if ($bug_assignee =~/PSEREP|SUNREP|PBUILD|BKPTRGQ/i)
        {
            $err_msg_tmp = "This request is now queued for " .
                           "manual processing.\n" . $bugdb_err_msg;
            $validated_assignee = 1;
            $assignee = $bug_assignee;
            $pse_status = $bug_status;
        }
	else
	{
	    ####################################################################################################################
	    ###### ER 33271480 - Update all messages on backport reassignment to developers with information about slack channel
	    ####################################################################################################################
	    
            $err_msg_tmp = $err_msg_tmp . "This request is now queued for " .
                           "manual processing.\n" . "If you have any questions about this, you can contact\n" .
			   "the automation team on slack channel - se_backport_auto:\n" .
			   "   https://proddev-tk-core.slack.com/archives/C6W7LTFB8\n" . "."; 
	}

        if (($testname =~ /APF-UNSUPPORTED-PRODUCT-RELEASE/i) ||
            ($testname =~ /APF-UNSUPPORTED-PROD-RELEASE/i))
        {
            $err_msg_tmp = "This request is now queued for " .
                           "manual processing. ";

        }

        $log_fh->print("\nCalled get_base_bug_owner:".
                       "$bug_assignee:$bug_status:\n");

        if ( $validated_assignee != 1)
        {
            my $call_cpm = 0;

            if ($ignore_cpm == 0)
            {
                my ($ci_request_id) = ARUDB::single_row_query(
                                      'GET_CI_REQUEST_ID', $bug);

                $call_cpm = 1 if($ci_request_id);
            }

            if ($call_cpm == 1)
            {
                my $flag = 'Y';
                $flag = 'N' if ($gen_or_port eq 'I');

                $log_fh->print("\nCalling cpm api for assignment:".
                               "$gen_or_port:$bug:...\n");
                ARUDB::exec_sp('aru_cumulative_request.cpm_assign_backport',
                               $bug, ['boolean',$flag],['boolean',$flag]);

                my $bug_status;
                ARUDB::exec_sp("bugdb.get_bug_status", $bug,
                               \$bug_status);

                $self->_update_bug($bug, {status     => $bug_status,
                                          test_name  => $testname,
                                          tag_name   => $tag_name,
                                          body       => $err_msg_tmp});
            }
            else
            {
                $self->_update_bug($bug, {status     => $pse_status,
                                          programmer => $assignee,
                                          test_name  => $testname,
                                          tag_name   => $tag_name,
                                          body       => $err_msg_tmp});
            }
        }

        #my $bug_text = "Please log a bug against 1057/BKPT_AUTO, if " .
        #               "there is any issue with automation";
        #$self->_update_bug($bug, {body => $bug_text});
    }

    #
    # Bug : 16402864
    # If Failed request is Diagnostic PSE update but with text
    #
    my ($base_bug, $utility_ver) =
        $preprocess->get_bug_details_from_bugdb($bug ,0);

    my $is_diagnostic = $preprocess->is_diagnostic($base_bug);

    if ($is_diagnostic && ($gen_or_port eq 'O'))
    {
       my $bug_body = "NOTE: this PSE is for an automated diagnostic patch. \n".
                  "For more details on the\n".
                  "process for Patch Delivery please see the following link:\n".
                  PB::Config::diag_fail_inst_url;

        $self->_update_bug($bug, { body  => $bug_body});
    }

    #
    # Bug : 16359815
    # need to assign 52/WLSFDREP for PSE/MLR
    #
    if ($gen_or_port eq 'O' || $gen_or_port eq 'M')
    {
        #
        # Check bugdb product id exists in
        # aru params.
        #
        my $is_patchq_prod = $self->is_patchQ_product($prod_id, $gen_or_port);

        $log_fh->print("PatchQ: $is_patchq_prod \n");

        #
        # For unsupported failures of PSEs
        # assign it to 52/PATCHQ always
        #
        if (($testname =~ /APF-UNSUPPORTED-PRODUCT-RELEASE/i) &&
            (($is_patchq_prod == 1) || ($gen_or_port eq 'O')))
        {
            $pse_status = 52;
            $assignee = 'PATCHQ';

            $log_fh->print("Assignee : $assignee \n");
        }
        else
        {
            my ($def_assignee, $status) = ARUDB::single_row_query(
                                          'GET_DEFAULT_ASSIGNEE', $pse);
            if($aru_obj->{release} =~  /^5\.5/ && #Hack Hack not to change assignee of patch for OAS 5.5
               ($aru_obj->{product_id} == 14667 || $aru_obj->{product_id} == 11903))
            {
                $def_assignee = APF::Config::oas_jenkins_bi_triagee; 
                $status = 52;      
            }
             
            $log_fh->print("Assignee: $def_assignee, $status \n");
            $def_assignee = "PATCHQ" if ($def_assignee eq "PSEREP");
            $def_assignee = "PATCHQ" if ($def_assignee eq "BKPTRGQ");
            $assignee = $def_assignee if $def_assignee ne '';

            if (($is_patchq_prod == 1) &&
                ( $gen_or_port eq 'O') && ($assignee ne "PATCHQ" ))
            {
                $assignee = "PATCHQ";
            }

        }

    }

    if ($gen_or_port eq 'O' && $testname =~/ADE-ERROR-fetch transaction name/i)
    {
        $log_fh->print("DEBUG: ADE TXN: Product id".
                       $preprocess->{product_id}."\n");
        $self->{product_id} = $preprocess->{product_id};
        $preprocess->{release_id} = $aru_rel_id
            if (! defined $preprocess->{release_id} ||
                $preprocess->{release_id} eq "");
        $preprocess->is_parallel_proc_enabled();

        if ($preprocess->{enabled} == 1)
        {
            #
            # Check the priority of the PSE
            #
            $log_fh->print("Entered the loop for parallel processing : $pse \n");
            my ($p_severity) = ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                                       $pse);


            if (! (defined $preprocess->{only_p1} && $preprocess->{only_p1} == 1 &&
                   $p_severity > 1))
            {
                $assignee = "PSEREP";
                $pse_status = 40;
                $self->{assignee_found} = 1;
                my $pse_test_name = APF::Config::parallel_pse_testname;
                eval {
                    my $bug_tag_msg =
                        ARUDB::exec_sf('bugdb.create_or_append_bug_tag',
                                       $pse,
                                       $pse_test_name);
                };
            }
        }
    }


    if ((! defined $self->{assignee_found} || $self->{assignee_found} != 1) &&
        (($gen_or_port eq 'O') || (($gen_or_port eq 'B' or $gen_or_port eq 'M') &&
        (($testname =~ /APF-FARM-/ && $testname =~ /HANDOVER/) ||
         ($testname =~/APF-FARM-JOB-FAIL/) ||($testname =~ /APF-FARM-ABORTED/) ||
         ($testname =~ /APF-FARM-FAIL/)))))
    {
        my $base_test_ref =
            APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                   request_id => $self->{request_id},
                                   pse    => $pse,
                                   log_fh => $self->{log_fh});
        my ($p_severity) = ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                                    $pse);

        my ($base_bug, $pse_version, $bugdb_platform_id, $bugdb_prod_id,
            $category, $sub_component);
        ($base_bug, $pse_version, $bugdb_platform_id, $bugdb_prod_id,
         $category, $sub_component) =
             $preprocess->get_bug_details_from_bugdb($pse, $is_autoport);


        my ($platform_id) = ARUDB::single_row_query("GET_APF_PLATFORM_ID",
                                                 $bugdb_platform_id);
        my ($product_id, $product_abbr);
        eval
        {
            ($product_id, $product_abbr) =
                APF::PBuild::Util::get_aru_product_id($bugdb_prod_id, $pse_version);
        };

        my @release_details =
            $preprocess->get_release_details($pse, $base_bug, $product_id, 1);

        my $cpct_release_id;
        my $is_cpct_release = ARUDB::exec_sf_boolean('aru.pbuild.is_cpct_release',
                                                     $pse,'',
                                                     \$cpct_release_id);

        if ($is_cpct_release)
        {
            @release_details = ARUDB::query('GET_RELEASE_INFO_CPCT',
                                            $cpct_release_id);
        }

        my ($release_id, $release_name, $rls_long_name);

        foreach my $current_release (@release_details)
        {
            ($release_name, $release_id, $rls_long_name) = @$current_release;
            #
            # for BPs & Psu releases, the pad_version of utility version returns
            # the same value
            #
            my ($bug_version) = ARUDB::single_row_query('GET_BUG_VERSION',$pse );
            last if ($bug_version =~/BUNDLE/) &&
                ($rls_long_name =~/BP/);
        }


        $log_fh->print("DEBUG: ADE TXN Product id : Product id".
                       "$product_id, $release_id \n");
        $base_test_ref->{product_id} = $product_id;
        $base_test_ref->{release_id} = $release_id;
        $base_test_ref->is_parallel_proc_enabled();

        my ($p_severity) = ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                                   $pse);

        if (! defined $base_bug || $base_bug eq "")
        {
            $base_bug = $pse;
        }

        if ($base_test_ref->{enabled} == 1)
        {
            $log_fh->print("DEBUG: Parallel processing is enabled : $pse \n");
            if (! ($base_test_ref->{only_p1} == 1 && $p_severity > 1))
            {
                if ($gen_or_port eq 'B' or $gen_or_port eq 'M')
                {
                    $self->{log_fh}->print("\nChecking if PSEs are in-progress ".
                                           "or completed, release id : $release_id \n");

                    my ($bugdb_blr_version) = ARUDB::single_row_query("GET_UTILITY_VERSION",
                                                                      $pse);

                    $log_fh->print("DEBUG: Utility Version :$bugdb_blr_version \n");

                    my (@pse_details) = ARUDB::query('GET_ALL_BUGDB_BACKPORT_PSES',
                                                     $base_bug,
                                                     $bugdb_blr_version);

                    # my (@pse_details) = ARUDB::query('GET_ALL_BACKPORT_PSES',
#                                                      $base_bug, $pse);
                    my $pses_found = 0;
                    foreach my $each_pse (@pse_details)
                    {
                        my ($blr_pse_bug, $sev) = @$each_pse;
                        $pses_found = 1;
                        my ($blr_pse_isd) =
                            ARUDB::single_row_query('GET_BLR_PSE_ISD_REQ',
                                                    $blr_pse_bug);
                        if (defined $blr_pse_isd && $blr_pse_isd ne "")
                        {
                            #
                            # abort pserequest
                            #
                            my $pse_bug_txt = "BLR/MLR Farm Job is Failed, Aborting the".
                                " PSE processing";
                            $log_fh->print("calling isd_request.abort_request for ".
                                           "$blr_pse_isd\n");

                            # ARUDB::exec_sp('isd_request.abort_request',
                            #                $blr_pse_isd,
                            #                1779908,
                            #                "Aborting the PSE reques, P1 Backport failed");

                            # $self->_update_bug($blr_pse_bug,
                            #                {status        => 40,
                            #                 programmer    => 'PSEREP',
                            #                 test_name     => '',
                            #                 body          => $pse_bug_txt });
                        }

                        #
                        # update the patch status to on-hold
                        #
                        my (@blr_pse_arus) = ARUDB::query("GET_BLR_PSE_ARUS",
                                                          $base_bug,
                                                          $release_id);
                        foreach my $each_aru (@blr_pse_arus)
                        {
                            my ($blr_pse_aru) = @$each_aru;

                            ARUDB::exec_sp("aru_request.update_aru",
                                           $blr_pse_aru,
                                           ARU::Const::patch_on_hold, "",
                                           ARU::Const::apf2_userid,
                                           "P1 Backport failed ");
                        }

                    }
                    $self->send_parallel_proc_abort_alert($pse, $log_fh)
                        if ($pses_found == 1);
                }
                elsif ($gen_or_port eq 'O')
                {
                    my $raise_exception = "y";
                    my $ignore_blr_status = "y";

                    $log_fh->print("DEBUG: Base Bug: $base_bug, $pse_version ".
                                   "$product_id \n");
                    my $pse_blr_bug = ARUDB::exec_sf('aru.bugdb.get_blr_bug',
                                             $base_bug, $pse_version,
                                             ['boolean',$raise_exception],
                                             $product_id,
                                             ['boolean',$ignore_blr_status]);


                    $log_fh->print("DEBUG: BLR Bug: $pse_blr_bug \n");
                    my ($pse_blr_status, $blr_prod_id, $blr_priority) =
                        ARUDB::single_row_query("GET_BUG_DETAILS_FROM_BUGDB", $pse_blr_bug);

                    $log_fh->print("DEBUG: BLR Bug Status: $pse_blr_status \n");

                    if ($pse_blr_status != 35)
                    {
                        $assignee = 'PSEREP';
                        $pse_status = 40;
                    }
                }
            }
        }
    }

    #
    # This is a temporary code change until invalid object regression gets stable
    #
    #enabling this code for bug:33716681
    if($testname eq "APF-FARM-INVALID-OBJECT-REGRESSIONS-HANDOVER" or
       $testname eq "APF-FARM-REGRES-INVALID-OBJ-REGRES-HANDOVER")
    {
     $assignee = 'PATCHQ';
    }

    $log_fh->print("Assignee: $assignee \n");
    $log_fh->print("utility version: $utility_ver \n");

    my $major_release = 0;
    $major_release = $1 if ($utility_ver =~ /(\d+).(\d+)/);

    #
    # set testname to APF-NORETRY if --datapatch option was used.
    # passing 0 for release since we don't need to set APF-NORETRY for
    # 12C and above anyway .
    #
    if($product_family=~ /orcl_pf/i and $gen_or_port eq 'O'
       and $major_release < 12)
    {
     my ($datapatch, $pre12) = APF::PBuild::Base::is_datapatch(
                      {log_fh=>$self->{log_fh}},
                      {release=>0,request_id=>$self->{params}->{request_id}});
     if($datapatch && $pre12)
     {
      $testname = 'APF-NORETRY-DATAPATCH';
     }
    }

    #
    # This feature is implemented to update bug with extra texts for
    # required testnames. We are maintaining an xml file that maps
    # testnames to extra bug text that is used to update bug .
    #
    $log_fh->print("searching custom bugtext\n");
    my ($custom_bugtext) =
          APF::PBuild::Util::get_testname_to_bug_text($testname);
    if($custom_bugtext)
    {
      $log_fh->print("found custom bugtext for testname $testname\n");
      $log_fh->print("Adding following text to bugdb message\n");
      $log_fh->print("$custom_bugtext\n");
      $err_msg_tmp = $custom_bugtext . $err_msg_tmp;
    }
    else
    {
     $log_fh->print("found no custom bugtext\n");
    }

    unless ($autoport)
    {
        if ($err_msg_tmp !~ /submitted for Install Test. APF will/)
        {
            my $tmp_testname = $testname;
            my $tmp_tag_name = $tag_name;

            if (($pse_status == 35) && (!$fusionapps_req))
            {
                $tmp_testname = $self->{copy_merge};
                $tmp_tag_name = $self->{copy_merge};

                $self->{die} = 0;

                ARUDB::exec_sp('apf_build_request.set_status_completed',
                               $pse, $tmp_testname,
                               'Successfully completed backport request.');
                $err_msg_tmp = "";
            }
            else
            {
               if (length($tmp_testname) > 49)
               {
                 $self->{log_fh}->print("$tmp_testname exceeds 50 chars\n");
                 $tmp_testname = substr($tmp_testname, 0, 45);
                 $tmp_tag_name = substr($tmp_tag_name, 0, 45);

                   if (length($err_msg_tmp) > 50)
                   {
                     $self->{log_fh}->print("$err_msg_tmp exceeds 50 chars \n");
                     $err_msg_tmp = substr($err_msg_tmp, 0, 45);
                   }

                 $self->{log_fh}->print("Trimmed: ".
                                        "$tmp_testname\n $err_msg_tmp\n");
               }

               ARUDB::exec_sp('apf_build_request.set_status_failed',
                               $pse, $tmp_testname,
                               "Request failed and assigned to " .
                               "$pse_status/$assignee");
            }

            $self->{log_fh}->print("\nChecking status for user:$assignee\n");

            #
            # Check assignee is valid or not before updating bug
            #
            my $user_status = $self->is_valid_user($assignee);

            $self->{log_fh}->print("\nUser($assignee) Status:$user_status:\n");

            unless ($user_status)
            {
                $self->{log_fh}->print("\nInvalid User:$assignee\n");

                my ($def_assignee, $status) = ARUDB::single_row_query(
                    'GET_DEFAULT_ASSIGNEE', $pse);

                $def_assignee = "PATCHQ" if ($def_assignee eq "PSEREP");
                $def_assignee = "PATCHQ" if ($def_assignee eq "BKPTRGQ");
                $assignee = $def_assignee if $def_assignee ne '';

                $self->{log_fh}->print("\nAssigning it to User:$assignee\n");
            }
            if ($err_msg =~ /Invalid PSE - Cloud PSE on BLR in unsupported/)
            {
                my $patch_escalation_email_id = APF::Config::patch_escalation_email_id;
                $pse_status  = 53;
                $err_msg_tmp = "This is a PSE filed on cloud BLR. ".
                               "This is not a valid use-case and ".
                               "hence it is marked as rejected. \n".
                               "Please contact a SE FD team representative ".
                               "by sending an email to $patch_escalation_email_id";
                $log_fh->print("It is a cloud PSE filed on BLR. Hence marking as rejected.\n");
            }

            elsif ($err_msg =~ /Invalid PSE - Cloud PSE is supported only on Linux/)
            {
                my $patch_escalation_email_id = APF::Config::patch_escalation_email_id;
                $pse_status  = 53;
                $err_msg_tmp = "Cloud patches are supported only for Linux x86-64(226) port. ".
                               "This PSE is not filed on the supported port and ".
                               "hence it is marked as rejected. \n".
                               "Please contact a SE FD team representative ".
                               "by sending an email to $patch_escalation_email_id";
                $log_fh->print("It is a cloud PSE filed on non Linux x86-64(226) port. Hence marking as rejected.\n");
            }
            elsif ($err_msg =~ /Invalid PSE - Cloud PSE is supported only for releases/)
            {
                my $patch_escalation_email_id = APF::Config::patch_escalation_email_id;
                $pse_status  = 53;
                $err_msg_tmp = "Cloud patches are supported only for releases 11.2.0.4 and 12.1.0.2(and it's overlays). ".
                               "This PSE is not filed on the supported release and ".
                               "hence it is marked as rejected. \n".
                               "Please contact a SE FD team representative ".
                               "by sending an email to $patch_escalation_email_id";
                $log_fh->print("It is a cloud PSE which is not filed on 11.2.0.4 and 12.1.0.2(and it's overlays). Hence marking as rejected.\n");
            }
            elsif ($err_msg =~ /Invalid PSE - The transaction contains a jox file/)
            {
                my $patch_escalation_email_id = APF::Config::patch_escalation_email_id;
                $pse_status  = 53;
                $err_msg_tmp = "Invalid PSE - The transaction contains a jox file. ".
                               "Hence it is not allowed have backport on RDBMS and PSE on JAVAM components. ".
                               "Hence it is marked as rejected. \n".
                               "Please contact a SE FD team representative ".
                               "by sending an email to $patch_escalation_email_id";
                $log_fh->print("Invalid PSE - The transaction contains a jox file. ".
                               "Hence it is not allowed have backport on RDBMS and PSE on JAVAM components. ".
                               "Hence marking as rejected.\n");
            }
            elsif ($err_msg =~ /Invalid PSE - This is a rare\(most of times incorrect\) combination of BLR on JAVAVM and PSE/)
            {
                my $patch_escalation_email_id = APF::Config::patch_escalation_email_id;
                $pse_status  = 52;
                $err_msg_tmp = "Possible incorrect PSE - The transaction contains jox file and ".
                               "backport is on JAVAVM and PSE on RDBMS component. This needs to be reviewed by Fix Delivery Team. ".
                               "Hence assigning the bug to FD team. \n".
                               "Please contact a SE FD team representative ".
                               "by sending an email to $patch_escalation_email_id";
                $log_fh->print("Possible incorrect PSE - The transaction contains jox file and ".
                               "backport is on JAVAVM and PSE on RDBMS component. This needs to be reviewed by Fix Delivery Team. ".
                               "Hence assigning the bug to FD team. \n");
            }
            if ( my ($trans,$l_assignee) = $err_msg 
                    =~ /The transaction (.*?) is already in closed state by (.*?) and contains the backend branched elements/)
            {
                $log_fh->print("DEBUG_RETRY: The transaction is already closed. ". 
                               "Hence not retrying.\n");
                $assignee      = $l_assignee;
                $pse_status    = 35;
                $tmp_testname  = "APF-RETRIED";
                $tmp_tag_name  = "APF-RETRIED";
                $err_msg_tmp   = "The transaction $trans is already closed. Hence not retrying";
               
                  $self->_update_bug($pse, {status        => $pse_status,
                         	            programmer    => $assignee,
                                            version_fixed => $utility_ver,
                                            tag_name      => $tmp_tag_name,
                                            body          => $err_msg_tmp});
            }
            else {


                  $self->_update_bug($pse, {status     => $pse_status,
                         	            programmer => $assignee,
                                            test_name  => $tmp_testname,
                                            tag_name   => $tmp_tag_name,
                                            body       => $err_msg_tmp})
                if ((($aru_rel_id =~
                        /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)||
                   (($validated_assignee == 1) ||
                    ($gen_or_port eq 'O' || $gen_or_port eq 'M' ))) && 
                   !($self->{fmw12c_skip_def_assignee}));

            }
        }
    }

    $base->free_throttle_resource($self->{request_id},
                                  ISD::Const::isd_request_stat_fail)
                                  if $base;

    if(defined($self->{aru_obj}->{bugdb_product_id}) &&
       ($self->{aru_obj}->{bugdb_product_id} == 10633))
    {
        $base->send_mail_notification($self->{base_bug}, 0);
    }

}




#
# Mechanism to retry the request, if it fails while ftping.
# See bug 9068720.
#
sub _handle_timeout
{
    my($self,$params)=@_;
    my $request_id   = $params->{request_id};
    my $user_id      = $params->{user_id};
    my $aru_no       = $params->{aru_no};
    my $bug          = $params->{bug};
    my $action       = $params->{action};
    my $start_time   = $params->{start_time};
    $self->{aru_obj} = $params->{aru_obj};

    my $retries      = PB::Config::ftp_retry_intervals;
    if (!$params->{retry_no})
    {
        $params->{retry_no}=0;
    }
    my $iteration    = ($params->{retry_no} || 0) + 1;
    if ($iteration <= @$retries)
    {
        my $wait_time     = int($retries->[$iteration - 1] * 60);
        $params->{retry_no} = $iteration;

        #
        # Modifying parameter to reflect current retry_no
        #
        ARUDB::exec_sp('isd_request.add_request_parameter', $request_id,
                       "st_apf_build","BUG:$bug!USER_ID:$user_id".
                       "!ARU_NO:$aru_no".
                       "!ACTION:$action".
                       "!START_TIME:$start_time".
                       "!RETRY_NO:$iteration");
        ARUDB::exec_sp('isd_request.enqueue_request', $request_id,
                       PB::Config::apf_grid_id,$wait_time);
        die("Action $action not completed, APF will retry ".
            "after $wait_time secs");
    }
    else
    {
        ARUDB::exec_sp('isd_request.abort_request',
                       $request_id,
                       $user_id,
                       "FTP connection timed out at the $action:action");

        die("Action $action failed as FTP connection timed out.".
            "Check log files for more details");
    }
}


#
# Updates the bugdb with the given status and assignee
#
# options will have keys like status, programmer, test_name, body,
# version_fixed
#
sub _update_bug
{
    my ($self, $bug, $options) = @_;
    $self->{log_fh} =  $self->{log_fh} ||$self->{aru_log};

    my $log_fh = $self->{log_fh};

    $options->{tag_name} = $options->{tag_name} || $options->{test_name};

    my $base =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                       request_id => $self->{request_id},
                                       pse    => $self->{params}->{bug} ||
                                           $self->{preprocess}->{pse},
                                       aru_obj => $self->{aru_obj},
                                       log_fh => $self->{log_fh});
    my ($is_fmw11g, $is_injection_level) = $base->is_fmw11g();
    $options->{programmer} = 'PATCHQ'
        if ($is_fmw11g == 1 && $options->{status} == 52);

    my $req_bug;
    my $is_autoport_enabled;

    if (defined($self->{aru_obj}->{aru}))
    {
        $req_bug = $self->{aru_obj}->{aru};
    }
    else
    {
        $req_bug = $bug;
    }

    my ($auto_isd_request_id) =
        ARUDB::single_row_query("GET_PSE_ISD_REQUEST", $req_bug);

    $log_fh->print("Request Bug: $req_bug\n" .
                   "AutoPort ISD Request ID: $auto_isd_request_id\n");

    my ($isd_params) =  ARUDB::single_row_query
        ("GET_ST_APF_BUILD", $auto_isd_request_id);

    my $autoport_req = 0;
    my $tmp_autoport_req = "";
    ($tmp_autoport_req) = $isd_params =~ m#\s*\!AUTO_PORT:\s*(.*)\!*\s*#g
                                               if($isd_params =~ /AUTO_PORT/);
    $autoport_req = (split(/\!/,$tmp_autoport_req))[0] if ($tmp_autoport_req);

    $self->{auto_blr} = $req_bug;

    my $is_autoport = 0;
    my $aruno = ($self->{aru_obj}->{aru})?
        $self->{aru_obj}->{aru} : $self->{aru_no};

    my $platform_id = defined($self->{platform_id})?
        $self->{platform_id}:$self->{aru_obj}->{platform_id};

    my $release_id = defined($self->{release_id})?
        $self->{release_id}:$self->{aru_obj}->{release_id};

    my $product_id = defined($self->{product_id})?
        $self->{product_id}:$self->{aru_obj}->{product_id};

    if($product_id eq '')
    {
        $product_id = defined($self->{preprocess}->{product_id})?
            $self->{preprocess}->{product_id}:'';
    }

    if($release_id eq '')
    {
        $release_id = defined($self->{preprocess}->{release_id})?
            $self->{preprocess}->{release_id}:'';
    }

    my ($parent_prod_id) =
        ARUDB::single_row_query("GET_PARENT_PRODUCT_ID",
                                $product_id,
                                $release_id);

    $log_fh->print("Parent Product ID: $parent_prod_id \n");

    if (($self->{product_id} eq APF::Const::product_id_rdbms ||
         $self->{aru_obj}->{product_id}
         eq APF::Const::product_id_rdbms ||
         $parent_prod_id eq APF::Const::product_id_rdbms) &&
        ($autoport_req != 0))
    {
        if ($autoport_req != 0) {
          my ($checkin_req_id) =
                 ARUDB::single_row_query("GET_ISD_CHECKIN_REQUEST", $bug);

          $log_fh->print("Checkin ISD Request ID: $checkin_req_id\n");

          $is_autoport= 1 if (!$checkin_req_id);
        }

    }

    if ( $is_autoport ==  1 )
    {
        $log_fh->print("\nBug cannot be updated for Auto Port\n");
        return;
    }


    #
    # Bug 17362048 : assign to user after installtest succeeds or fails
    # for Database products. Identify if its an RDBMS patch and then
    # fetch the assignee
    #
    my ($isd_req_type_code) = ARUDB::single_row_query("GET_REQUEST_TYPE_CODE",
                                                      $self->{request_id});

    if ($isd_req_type_code == ISD::Const::st_apf_install_type &&
        $base->is_rdbms($bug))
    {
        if (! defined $self->{do_not_override_prog} ||
            $self->{do_not_override_prog} != 1)
        {
            $options->{programmer} =
                $self->_get_install_test_submit_user($self->{request_id});
        }

         if($self->{bugfix_request_id})
         {
             my $gen_or_port = $base->get_gen_port($bug);

             if ($gen_or_port eq 'B' || $gen_or_port eq 'M')
             {
                 $log_fh->print("\n$bug Bug cannot be updated for Auto Port, " .
                                "gen_or_port=$gen_or_port\n");
                 return;
             }
         }

     }

    #
    # die if $bug is null
    # Exception: For AutoPort patches, the bug details wouldn't be present.
    #
    unless ($bug)
    {
        my ($pkg, $filename, $line) = caller;

        $log_fh->print("update_bug called without bugno:\n");
        $log_fh->print("Caller : $pkg (line no $line)\n");
        $log_fh->print("with following Options : \n");

        $log_fh->print("\t Programmer : $options->{programmer}\n".
                                "\t Status : $options->{status}\n" .
                                "\t Test Name : $options->{test_name}\n".
                       "\t Version Fixed : $options->{version_fixed}\n");

        my $aru = $self->{bugfix_request_id};
        my $pse = $self->{params}->{bug} || $self->{preprocess}->{pse};

        $log_fh->print("ARU: $aru; PSE: $pse \n");

        die("Bug number is empty, BUG DB cannot be updated.")
            unless  ((defined ($aru) and $aru ne '') && (!$pse));
    }

    if ($bug)
    {
        #
        # Incase if aru number is passed in place of bug number
        #
        if ($bug eq $self->{bugfix_request_id})
        {

            ($bug) = ARUDB::single_row_query("GET_PSE_BUG_NO",
                                             $self->{bugfix_request_id});
        }

        my $bugfix_request_id = $self->{bugfix_request_id};
        my $aru_obj  =
         (defined $self->{aru_obj}->{aru}) ? $self->{aru_obj} :
               new ARU::BugfixRequest($bugfix_request_id);

        my ($aru_release_id, $bugdb_gen_or_port);

        if ($aru_obj->{bugfix_id})
        {
            $aru_obj->get_details();
            $self->{aru_obj} = $aru_obj;

            ($aru_release_id) =  $aru_obj->{release_id};
        }

        my $disable_bug_updates = APF::Config::disable_bug_updates;

        unless ($aru_release_id)
        {
            my ($bugdb_platform_id, $bug_prod_id, $bug_comp);

            if (defined $aru_obj->{$bug}->{rptno} &&
                $aru_obj->{$bug}->{rptno} ne "")
            {
                ($bugdb_platform_id, $bugdb_gen_or_port, $bug_prod_id,
                 $bug_comp) = ($aru_obj->{$bug}->{platform_id},
                               $aru_obj->{$bug}->{gen_or_port},
                               $aru_obj->{$bug}->{product_id},
                               $aru_obj->{$bug}->{bug_comp});
                $log_fh->print("Bug details from DB: ".
                                      "$bugdb_platform_id, $bugdb_gen_or_port".
                                      "$bug_prod_id,$bug_comp \n");
            }
            else
            {
                ($bugdb_platform_id, $bugdb_gen_or_port, $bug_prod_id,
                 $bug_comp) = ARUDB::single_row_query('GET_BUG_INFO',
                                                      $bug);
            }

            my ($aru_prod_id) =
                ARUDB::exec_sf('aru.aru_product.find_bug_product',
                               $bug_prod_id, $bug_comp);

            ($aru_release_id) = ARUDB::single_row_query('FETCH_RELEASE_ID',
                                                        $aru_prod_id);
        }

        #
        # Gen_or_port is not defined if aru_release_id is. Need to add this
        # query in case it is not fetched.
        #
        unless ($bugdb_gen_or_port)
        {
            my ($bugdb_platform_id, $bug_prod_id, $bug_comp);
            ($bugdb_platform_id, $bugdb_gen_or_port, $bug_prod_id, $bug_comp)
                = ARUDB::single_row_query('GET_BUG_INFO', $bug);
        }

        my $on_hold_patch = 0;
        if (defined $options->{on_hold_patch} &&
            $options->{on_hold_patch} == 1)
        {
            $on_hold_patch = 1;
            my $gen_or_port = $base->get_gen_port($bug);
            if (($options->{status} == 55) &&
                ($gen_or_port ne "I" && $gen_or_port ne "O" &&
                 $gen_or_port ne "B" && $gen_or_port ne "M"))
            {
                $self->{log_fh}->print("Gen/Port should be I/O/B/M for ".
                                       "updating the bug status to 55.\n");
                $on_hold_patch = 0;
            }
        }

        $options->{version_fixed} == ""
            if ($options->{status} == 11);

        #
        # If the bug is already released, do not release_id it again
        #
        my ($l_status, $l_ver_fixed, $test_name) =
            ARUDB::single_row_query("GET_SUSPENDED_BUG_DETAILS",
                                    $bug);

        $log_fh->print("Bug: $bug, Status: $l_status, " .
                       "Test Name: $test_name, " .
                       "Gen/Port: $bugdb_gen_or_port\n");

        unless  ( $aru_release_id =~
                  /^${\ARU::Const::applications_fusion_rel_exp}\d+$/
                  && defined $disable_bug_updates &&  $disable_bug_updates == 1
                  && ($on_hold_patch == 0))
        {
            #
            # Determine and assign bugs to APF Triage Queue
            #
            my $sla_enabled = APF::Config::sla_enabled;
            if (($sla_enabled) &&
                ($bugdb_gen_or_port eq "O") && ($l_status < 80)) {
              my ($sla_status, $sla_assignee) =
                   $self->_get_sla_info($bug, $options->{status}, $test_name);

              if (($sla_status ne "") && ($sla_assignee ne "")) {
                $options->{status} = $sla_status;
                $options->{programmer} = $sla_assignee;
                $log_fh->print("SLA Details:\n" .  "Status:\t$sla_status, " .
                               "Assignee:\t$sla_assignee\n");
                my $patch_escalation_email_id =
                        APF::Config::patch_escalation_email_id;
                $options->{body} =
                     "This request is now queued for SE Automation " .
                     "triage processing. \nIf this request requires " .
                     "immediate attention, please contact \n" .
                     "a SE FD team representative by sending an email to \n".
                     "$patch_escalation_email_id";
              }
            }

            my @upd_params = (
                    {
                     name  => 'pn_bug_number',
                     data  => $bug,
                    },
                    {
                     name  => 'pn_status',
                     data  => $options->{status},
                    },
                    {
                     name   => 'pv_programmer',
                     data   => $options->{programmer},
                    },
                    {
                     name   => 'pv_version_fixed',
                     data   => $options->{version_fixed},
                    },
                    {
                     name   => 'pv_tag',
                     data   => $options->{tag_name},
                    },
                   );

            if($options->{test_name}=~/NORETRY/)
            {
             push(@upd_params,{name=>'pv_test_name',
                               data=>$options->{test_name},});
            }
            else
            {
             push(@upd_params,{name=>'pv_test_name',
                               data=>'',});
            }

            #
            #  Do not reopen PSE if that one closed already
            #
            if (($l_status > 80) && ($bugdb_gen_or_port eq "O"))
            {
                $log_fh->print("Bug $bug was already closed, not " .
                               "updating it to $options->{status} \n");
            }
            else
            {
                ARUDB::exec_sp('bugdb.async_update_bug',@upd_params)
                        if ($options->{status});

                if ($options->{test_name})
                {
                    sleep(5);

                    my ($tracking_grp) =
                          ARUDB::single_row_query('GET_AUTO_TRACKING_GROUP',
                                                  $bug);

                    my $error_msg;
                    if($tracking_grp!~/APF-FMW-BASELINE|APF-FMW-TEST/)
                    {
                     ($error_msg) =
                        ARUDB::exec_sf("pbuild.create_tracking_grp_for_bug",
                                       $bug,'',
                                       $options->{test_name},'','%');
                    }

                    $log_fh->print("Error:$error_msg\n")
                        if ($error_msg);
                }
            }


            sleep(5);
        }

        #
        # Update the bug db with the msg
        #
        if ($options->{body})
        {
            chomp ($options->{body});
            ARUDB::exec_sp('bugdb.async_create_bug_text',
                           $bug,
                           $options->{body});
           sleep(5);
        }
    }

}

sub _get_sla_info {

  my ($self, $bug, $bug_status, $test_name) = @_;

  my $sla_assignee = "";
  my $sla_status = "";
  $self->{handle_failure} ||= 0;

  return ($sla_status, $sla_assignee)
     if (($bug_status =~ /35|80|90|93/) || ($self->{handle_failure} == 0));

  my ($abstract, $category, $gen_or_port, $priority, $port_id, $prod_id);
  eval {
    ARUDB::exec_sp("bugdb.get_bug_info",
                   $bug, \$abstract, \$category, \$gen_or_port,
                   \$priority, \$port_id, \$prod_id);
  };

  return ($sla_status, $sla_assignee)
              if (($priority == 1) || ($gen_or_port ne 'O'));

  my ($utility_ver) = ARUDB::single_row_query('GET_UTILITY_VERSION', $bug);
  my ($product_id, $product_abbr) =
        APF::PBuild::Util::get_aru_product_id($prod_id, $utility_ver);
  $product_abbr ||= "";
  return ($sla_status, $sla_assignee)
         if ($product_abbr ne APF::Const::const_orcl_pf);

  my $bug_rptdate = "";
  my $bug_rptdays = 0;
  my $sla_maximum_days = APF::Config::sla_maximum_days;

  eval {
    ($bug_rptdate, $bug_rptdays) =
          ARUDB::single_row_query('GET_BUG_REPORTED_DATE',$bug );
  };
  $bug_rptdays ||= 0;

  $self->{log_fh}->print(
         "SLA Max days:\t$sla_maximum_days, " .
         "Bug Reported on:\t$bug_rptdate, " .
         "Elapsed Days:\t$bug_rptdays, " .
         "Bug:\t$bug, " .
         "Status:\t$bug_status, " .
         "Generic or PortSpecific:\t$gen_or_port\n") if ($self->{log_fh});

  return ($sla_status, $sla_assignee)
    if ($bug_rptdays > $sla_maximum_days);

  my @patterns;
  my $slafl = "$ENV{ISD_HOME}/conf/sla_test_names.lst";

  return ($sla_status, $sla_assignee) if (!-e $slafl);

  my $sfl = new SimpleFileLoader($slafl, '#') ||
                  return ($sla_status, $sla_assignee);
  @patterns = $sfl->get_lines();

  if (!(grep(/^$test_name/, @patterns))) {
    $sla_assignee = APF::Config::sla_assignee;
    $sla_status = APF::Config::sla_bug_status;
  }

  return ($sla_status, $sla_assignee);
}

#
# Run GSCC on the transaction involved in the patch creation.
# Grabs the transaction to the already created view in the previous step of
# Preprocess and run GSCC on the changed files. Once done, destroy the view.
#
sub _run_gscc
{
    my ($self, $transaction_name, $aru_obj, $label) = @_;

    my $view_name = $ENV{USER} . "_local_" . $aru_obj->{aru};

    my $bugfix = $aru_obj->get_bugfix();
    $bugfix->get_master();
    my $bugfix_id = $bugfix->{bugfix_id};

    require GSCC::ARUDataAccessor;
    require GSCC::CheckinObject;

    my $accessor       = new GSCC::ARUDataAccessor();
    my $checkin_obj    = new GSCC::CheckinObject();

    #
    # Setting required parameters for the Checkin Object.
    #
    $checkin_obj->set_parameter("RELEASE", $bugfix->{release_name});
    $checkin_obj->set_parameter("IS_APF", 1);
    $checkin_obj->set_parameter("BUGFIX_ID", $bugfix_id);
    $checkin_obj->set_parameter("BUGFIX_NUM", $bugfix->{bug});
    $checkin_obj->set_parameter("PHASE", ARU::Const::gscc_phase_source);
    $checkin_obj->set_parameter("REQUESTED_BY", $aru_obj->{requested_by});
    $checkin_obj->set_parameter("RELEASE_LONG_NAME",
                                $bugfix->{release_long_name});

    my $ade_obj = new SrcCtl::ADE({no_die_on_error => 'YES'});
    $ade_obj->set_filehandle($self->{request}{log});

    #
    # Check whether the GSCC results for this checkin are already uploaded
    # to the database during any previous pse requests.
    #
    my $files_and_standards =
        $accessor->get_files_standards_for_checkin($checkin_obj);
    my $file_and_standard = $$files_and_standards->next_row();

    #
    # Proceed only if the the GSCC results are not in database.
    #
    if (defined $file_and_standard)
    {
        #
        # Setting the GSCC status to unknown in the beginning of processing.
        #
        my ($status, $sf_error) =
            ARUDB::exec_sf('gscc.set_bugfix_gscc_status',
                           $bugfix_id,
                           ARU::Const::gscc_bugfix_unknown);

        #
        # Create a view if required.
        #
        $ade_obj->create_view($label, $view_name,
                              (noexpand => 'Y', force => 'Y'));

        my $view_obj = $ade_obj->use_view($view_name);
        $view_obj->set_filehandle($self->{request}{log});

        my $view_root;
        #
        # If any of the following command fails, we should not cause the entire
        # patch build process to fail. We just need to skip GSCC and pass
        # control to next step.
        #
        eval
        {
            #
            # Grab the transaction to the view.
            #
            $ade_obj->grab_transaction($view_obj, $transaction_name);
            $view_root = $view_obj->get_view_directory();
        };

        unless($@)
        {
            chdir "$view_root";

            require GSCC::BugfixDataAccessor;
            require GSCC::Engine;

            my $patch_accessor = new GSCC::BugfixDataAccessor();
            $patch_accessor->set_parameter('BUGFIX_ID', $bugfix_id);

            my $gscc_engine    = new GSCC::Engine();

            #
            # Running GSCC for Files.
            #
            my ($result, $status) =
                $gscc_engine->process($checkin_obj,
                                      $accessor,
                                      $self->{request}{log});
            #
            # Running Patch Checks
            #
            my ($patch_result, $patch_status) =
                $gscc_engine->process($checkin_obj,
                                      $patch_accessor,
                                      $self->{request}{log});

           #
           # update with final status
           #
            my $gscc_status = ARUDB::exec_sf('gscc.update_bugfix_gscc_status',
                                             $bugfix->{bugfix_id});
        }
        else
        {
            $self->{request}{log}->print("ERROR:\n");
            $self->{request}{log}->print($@);
        }
    }
    else
    {
        my $message =
            "GSCC did not run on the files included in this patch ".
            "because of one of the following reasons.\n" .
            " 1. There are no standards enforced for this release which are\n".
            "    applicable to the files in this patch.\n" .
            " 2. GSCC had already run for this checkin.\n";

        $self->{request}{log}->print($message . "\n");
    }

    #
    # Abort the txn before destroying the view
    #
    my $cmd = "ade pwv -view " . $view_name;
    $ade_obj->do_cmd_ignore_error(
               $cmd,(keep_output => 'YES',
                     timeout => PB::Config::ssh_timeout));

    my (@output) = $ade_obj->get_last_do_cmd_output();

    foreach my $line (@output)
    {
        chomp($line);
        $line =~ s/ //g;
        my ($v_key, $v_value) = split(/:/,$line);
        if (lc($v_key) eq "view_txn_name")
        {
            if ($v_value !~ /NONE/i)
            {
                $cmd =<<"CMD";
ade useview $view_name <<EOF
ade unco -all
ade unbranch -all
ade aborttrans -force -purge -no_restore -rm_properties
ade destroytrans -force $v_value
EOF
CMD

                $ade_obj->do_cmd_ignore_error
                    ($cmd,(keep_output => 'YES',
                           timeout => PB::Config::ssh_timeout));
                last;
            }
        }
    }

    eval {
        #
        # Destroy the view.
        #
        $ade_obj->destroy_view($view_name)
            if (-e "/ade/$view_name");
    };

}


#
# Performs remaining actions after preprocessing
# a:packages the patch
# b:pushes the patch to repository
#
sub _postprocess
{
    my ($self, $params)   = @_;
    my $log_fh            = $self->{aru_log};
    my $work_area         = $self->{aru_dir};
    my $bugfix_request_id = $params->{aru_no};
    my $pse               = $params->{bug};
    my $is_saoui               = $params->{is_saoui};
    my $is_sa               = $params->{is_sa};
    my $is_oui               = $params->{is_oui};
    $self->{bugfix_request_id} = $bugfix_request_id;
    my $oms_rolling       = $params->{oms_rolling};
    my $is_discover       = $params->{is_discover};
    my $plugin_type       = $params->{plugin_type};
    my $em_product_id = $params->{em_product_id};
    my $em_release_id = $params->{em_release_id};
    my $em_release_name = $params->{em_release_name};
    my $em_metadata_xml = $params->{em_metadata_xml};
    my $sql_files = $params->{sql_files};
    my $fixed_bugs = $params->{fixed_bugs};

    $params->{action}      = 'postprocess';

    my $aru_obj;

    if (defined $self->{aru_obj}->{aru})
    {
        $aru_obj = $self->{aru_obj};
    } else
    {
        $aru_obj = new ARU::BugfixRequest($bugfix_request_id);
        $aru_obj->get_details();
    }

    $self->{bugfix_request_id} = $aru_obj->{aru};
    $params->{start_time}  = $aru_obj->{requested_date};
    $aru_obj->{transaction_details} = $params->{online};
    $aru_obj->{blr}       = $params->{blr};
    my $post_proc = APF::PBuild::PostProcess->new($aru_obj, $work_area,
                                                  $log_fh, $aru_obj->{aru});

    $post_proc->{bugfix_request_id} = $bugfix_request_id;
    $post_proc->{psu}               = $self->{psu};
    $post_proc->{bpr_label} = $params->{bpr_label} || $self->{bpr_label};
    $post_proc->{ade_view_root}     = $params->{ade_view_root};
    $post_proc->{ade_view_name}     = $params->{ade_view_name};
    $post_proc->{ade_trans_name}    = $params->{ade_trans_name};
    $post_proc->{fa_prodfam_label}  = $params->{fa_prodfam_label};
    $post_proc->{bugdb_prod_id}     = $self->{bugdb_prod_id};
    $post_proc->{is_saoui}   = $is_saoui;
    $post_proc->{is_sa}      = $is_sa;
    $post_proc->{is_oui}     = $is_oui;
    $post_proc->{oms_rolling}     = $oms_rolling;
    $post_proc->{fixed_bugs}     = $fixed_bugs;
    $post_proc->{request_id} = $self->{request_id};
    #
    # enable em ps2 agent, bug 17358015, packaging should not use
    # second template for agent
    #
    $post_proc->{em_product_id} = $em_product_id;
    $post_proc->{em_release_id} = $em_release_id;
    $post_proc->{em_release_name} = $em_release_name;
    $post_proc->{em_metadata_xml} = $em_metadata_xml;
    $post_proc->{sql_files} = $sql_files;

    #
    # Generating the README and Template again for OBIEE.
    #
    if (($self->is_bi_product($aru_obj->{product_id})) and
        ($aru_obj->{platform_id} != ARU::Const::platform_generic))
    {

        $log_fh->print_header("Generate README");
        $params->{action_desc} = 'Generate README';
        my $preprocess = APF::PBuild::PreProcess->new($params);
        $preprocess->preprocess($self->{bugfix_request_id});
        my ($base_bug, $utility_ver, $platform_id, $bugdb_prod_id,
            $category, $sub_component) =
                $preprocess->get_bug_details_from_bugdb($pse ,0);

        $preprocess->{bugdb_prod_id}   = $bugdb_prod_id;
        $preprocess->{platform_id}     = $platform_id;
        $preprocess->{utility_version} = $utility_ver;
        $preprocess->{aru_obj}         = $aru_obj;
        $preprocess->{log_fh}          = $log_fh;
        my $gen_or_port = $preprocess->get_gen_port($params->{backport_bug});
        $preprocess->generate_readme($aru_obj->{aru}, $self->{output_dir});
        my $fixedbugs = $preprocess->{fixedbugs};

        $aru_obj->{transaction_details} = $preprocess->{transaction_details};

        #
        # Now we need to fetch the deliverables from farm to the workarea.
        # And cleanup the view.
        #
        # With support of other products, we always submit farm build for
        # Linux platform. We will perform diff on the Linux farm and convert
        # the deliverables to the target platform.
        #
        $log_fh->print_header("Retrieve DOs and Perform Diff");
        $params->{action_desc} = 'Retrieve DOs and Perform Diff';

        #
        # Get the farm dos directory for the targetted platform if it is not
        # Linux/Generic.
        #
        my $is_non_linux = 0;
        my ($tgt_base_label, $tgt_do_loc, $tgt_prod_top);
        if (($platform_id != ARU::Const::platform_linux) and
            ($platform_id != ARU::Const::platform_linux64_amd) and
            ($platform_id != ARU::Const::platform_generic_bugdb))
        {
            $is_non_linux = 1;
            ($tgt_base_label, $tgt_do_loc, $tgt_prod_top) =
                APF::PBuild::BI::Util::get_farm_job_details(
                                             $pse,
                                             $platform_id,
                                             $preprocess->{system},
                                             $log_fh);
            $tgt_do_loc .= "/dist/stage";
            die ("Error: Unable to find DOs from farm: $tgt_do_loc\n")
                if (! -e $tgt_do_loc);
            $log_fh->print("Targetted Farm DO location: $tgt_do_loc\n");
        }

        #
        # Now get the the details for Linux farm job.
        #
        my ($ip_base_label, $do_loc, $product_top) =
            APF::PBuild::BI::Util::get_farm_job_details(
                                             $pse,
                                             ARU::Const::platform_linux64_amd,
                                             $preprocess->{system},
                                             $log_fh);

        $do_loc .= "/dist/stage";
        die ("Error: Unable to find DOs from farm: $do_loc\n")
            if (! -e $do_loc);

        $log_fh->print("Farm DO location: $do_loc\n");

        #
        # Find the base label DOs location.
        #
        my $system = $preprocess->{system};
        my $base_do_loc =
            APF::PBuild::BI::Util::get_labelserver($ip_base_label, $system);
        $base_do_loc .= "/dist/stage";
        die ("Error: Unable to find DOs from base: $base_do_loc\n")
            if (! -e $base_do_loc);

        $log_fh->print("Base DO location: $base_do_loc\n");

        #
        # Do the diff between the two directories: Base and Farm DO.
        #
        my $ignore_files_list = PB::Config::bi_ignore_files;
        $log_fh->print("Ignore file list: @$ignore_files_list\n");

        my $diff_obj = APF::PBuild::BI::DiffTool->new
                ({log_fh         => $log_fh,
                  bpr_label      => $self->{bpr_label},
                  system         => $preprocess->{system},
                  filelist       => $self->{filelist},
                  ignore_list    => $ignore_files_list,
                  patch_type     => "non_bundle",
                  injection_level_patching => 1,
                  work_area      => $self->{aru_dir}});

        $diff_obj->{aru_obj} = $aru_obj;
        my $template         = $self->{aru_dir} . "/" .
                               $bugfix_request_id . "." ."tmpl";

        my ($extn_ref, $arch_ref) =
            $diff_obj->bi_compare_directories($base_do_loc,
                                              $do_loc);

        $log_fh->print("\nextn_ref:\n" . Dumper($extn_ref));
        $log_fh->print("\narch_ref:\n" . Dumper($arch_ref));

        my ($copy_list, $jar_list, $deliverables) =
            $diff_obj->bi_gen_inj_tmpl_lines($extn_ref, $arch_ref,
                                             $is_non_linux,
                                             { do_loc      => $do_loc,
                                               tgt_do_loc  => $tgt_do_loc,
                                               platform_id => $platform_id,
                                               log_fh      => $log_fh,
                                               aru_dir     => $self->{aru_dir}}
                                             );

        $log_fh->print("JAR_LIST = $jar_list\n");
        $log_fh->print("COPY_LIST = $copy_list\n");
        $log_fh->print("Deliverables = $deliverables\n");

        $log_fh->print_header("Create Template");
        $params->{action_desc} = 'Create Template';
        my ($psu_base_rls_id, $psu_base_rls_name) =
            $preprocess->get_base_release_info($preprocess->{release_id});

        my $component = "oracle.bi.$product_top";
        $diff_obj->bi_create_tmpl($template,
                    {fixed_bugs     => $fixedbugs,
                     exp_fixed_bugs => $preprocess->{expanded_fixed_bugs},
                     psu_bug        => $preprocess->{psu_bug_number},
                     platform_id    => $platform_id,
                     is_non_linux   => $is_non_linux,
                     copy_list      => $copy_list,
                     jar_list       => $jar_list,
                     is_injection   => 1,
                     pse            => $preprocess->{bug},
                     version        => $psu_base_rls_name,
                     do_loc         => $do_loc,
                     tgt_do_loc     => $tgt_do_loc,
                     aru_dir        => $self->{aru_dir},
                     deliverables   => $deliverables,
                     component      => $component });


        #
        # Delete the view. And also the Linux view if this is for other
        # platforms.
        #
        my $destroyview_cmd = "ade destroyview local_$bugfix_request_id -force";
        $system->do_cmd_ignore_error($destroyview_cmd,
                                     (keep_output => 'YES',
                                      timeout => PB::Config::ssh_timeout));

        if ($is_non_linux)
        {
            $destroyview_cmd = "ade destroyview local_$bugfix_request_id" .
                               "_linux64 -force";
            $system->do_cmd_ignore_error($destroyview_cmd,
                                         (keep_output => 'YES',
                                          timeout => PB::Config::ssh_timeout));

        }
    }

    $log_fh->print_header("Package the Patch");
    $params->{action_desc} = 'Package the Patch';

    $log_fh->print("DEBUG: Package: ARU PSE : ".
                   "$self->{aru_obj}->{ARU_PSE_BUG},".
                   "$aru_obj->{ARU_PSE_BUG} \n");
    if ($self->{bugdb_prod_id} != ARU::Const::product_bugdb_beaowls)
    {
        $post_proc->package();
    }
    else
    {
        $post_proc->copy_patch_to_transient_dir();
    }

    $log_fh->print_header("Enqueued to Repository Loader");
    $params->{action_desc} = 'Enqueued to Repository Loader';

    eval {
        $post_proc->push_to_patch_repository();

        $log_fh->print("P1 PSE Exception: Updating the Patch to On Hold\n");

        my $is_parallel_pse = 0;
        $self->is_parallel_proc_enabled();
        if ($self->{enabled} == 1)
        {
            my ($p_blr_sev) =
                ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                        $aru_obj->{blr})
                        if($aru_obj->{blr});

            if (!($self->{only_p1} == 1 && defined $p_blr_sev &&
                  $p_blr_sev > 1))
            {
                $is_parallel_pse = 1;
            }
        }

         my $p1_pse_request = $self->is_p1_pse_exp_enabled($aru_obj->{blr})
             if($aru_obj->{blr});

        if($p1_pse_request == 1 || $is_parallel_pse == 1)
        {
            ARUDB::exec_sp("aru_request.update_aru", $bugfix_request_id,
                           ARU::Const::patch_on_hold,
                           "", ARU::Const::apf2_userid,
                           'P1_PSE_EXCEPTION_REQUEST');
        }

    };

    #
    # Retry postprocess if FTP connection is timed out
    #
    if($@ =~ /Connection timed out/)
    {
        $self->_handle_timeout($params);
    }

    # fix for 13241776
    # set oms_rolling tag for
    # em rolling patches

    $log_fh->print("oms_rolling value = $oms_rolling \n");
    if ($oms_rolling == 1 &&
        ($aru_obj->{product_id} == ARU::Const::product_smp_pf ||
         $aru_obj->{product_id} == ARU::Const::product_emgrid))
    {
       $log_fh->print("setting emoms rolling tag \n");
       ARUDB::exec_sp('aru_bugfix.add_tag',
          $aru_obj->{bugfix_id},
          ARU::Const::emomsrolling_tag);

    }

    #
    # For em12c plugins, there are multiple releases for each plugin
    # based on if patch is for oms or agent
    # we need to know if this is agent plugin or oms plugin or
    # discovery plugin. If it is discovery plugin, then set a tag
    # 'EMDiscovery'
    # apf bug 16276795
    #
    if ( (($is_discover == 1) && ($plugin_type eq 'Agent')) &&
         (($aru_obj->{product_id} == APF::Const::product_id_emdb) ||
         ($aru_obj->{product_id} == APF::Const::product_id_emas) ||
         ($aru_obj->{product_id} == APF::Const::product_id_emfa) ||
         ($aru_obj->{product_id} == APF::Const::product_id_emmos)))
    {
       $log_fh->print("setting plugin discover tag  \n");
       ARUDB::exec_sp('aru_bugfix.add_tag',
          $aru_obj->{bugfix_id},
          APF::Const::emplugindiscover_tag);
    }

    #
    # For Fusion we don't run Install Test
    # So release patch after patch is built successfully
    #
    if ($aru_obj->{release_id}  =~
        /^${\ARU::Const::applications_fusion_rel_exp}\d+$/)
    {
        $log_fh->print_header("Release Patch");
        $params->{action_desc} = 'Release Patch';

        my $version = $params->{utility_version};
        $version = APF::PBuild::Util::get_version($version);

        $pse = $aru_obj->{bug} if ($aru_obj->{bug} && !$pse);

        $log_fh->print("Bug:\t$pse\n");
        $log_fh->print("Version:\t$version\n");
        $log_fh->print("ARU:\t$bugfix_request_id\n");
        $log_fh->print("PlatformID:\t$aru_obj->{platform_id}\n");
        $log_fh->print("Platform:\t$aru_obj->{platform}\n");
        $log_fh->print("ReleaseID:\t$aru_obj->{release_id}\n");

        $self->release_fusion($bugfix_request_id,$pse,$version,$aru_obj);
        $log_fh->print("\nPatch Released Internally and available ".
                       "for download through ARU\n\n");
        if (($aru_obj->{language_id} == ARU::Const::language_US) &&
            (($aru_obj->{platform_id} == ARU::Const::platform_generic) ||
            ($aru_obj->{platform_id} == ARU::Const::platform_linux64_amd))
        )
        {
         $self->update_skip_bugs($aru_obj, 1);
        }
    }


    #
    # If Diagnostic Patch update bug with instructions
    #
    my $is_diagnostic = ARUDB::exec_sf('aru.pbuild.is_diagnostic_patch',
        $self->{preprocess}->{base_bug});

    if( $is_diagnostic == 1)
    {
        my $tag_name = "APF";
        my $version = $params->{utility_version};
        $version = APF::PBuild::Util::get_version($version);
        $pse = $aru_obj->{bug} if ($aru_obj->{bug} && !$pse);

        my $upd_text = "\n".'----------------------------------------'."\n".
               'Diagnostic patch uploaded to ARU \'By Dev.\' '           .
               'To obtain password follow the instructions at link  '."\n".
               'https://confluence.oraclecorp.com/confluence/display/SE/Password+For+Diag+Patches'."\n"                .
                            '----------------------------------------'."\n\n";

        $self->_update_bug($pse, {
                            test_name     => 'APF',
                            tag_name      => $tag_name,
                            version_fixed => $version,
                            body          => $upd_text});

    }

}

sub update_skip_bugs
{
  my ($self, $aru_obj, $build_status) = @_;
  my $log_fh            = $self->{aru_log};

  $log_fh->print("\nFinding skipped bugs \n\n");

  return if(not defined $aru_obj);

  my $skip_hierarchy = ARUDB::exec_sf('pbuild.get_skip_hierarchy',
                                      $aru_obj->{aru});
  $log_fh->print("\nSkipped List : $skip_hierarchy \n\n");

  return if(!$skip_hierarchy);

  $skip_hierarchy=~s/,$//;
  $skip_hierarchy = $aru_obj->{aru} . "," . $skip_hierarchy;

  my @skip_list = split(/,/,$skip_hierarchy);

  for (my $count = 0; $count < (scalar(@skip_list) - 1) ; $count++)
  {
   my ($skip_aru,$superset_aru);
   if($skip_list[$count] eq $aru_obj->{aru})
   {
     $skip_aru = $skip_list[$count];
     $superset_aru = "";
   }
   else
   {
     ($skip_aru,$superset_aru) = split(/\-/,$skip_list[$count]);
   }
   my @skip_bb_details = ARUDB::query('GET_FUSION_BACKPORT_BUG',
                                      $skip_aru);
   my ($skip_backport_bug, $skip_base_bug, $skip_bugfix_id,
       $skip_patch_type);
   foreach my $skip_bb_rec (@skip_bb_details)
   {
    ($skip_backport_bug, $skip_base_bug,
     $skip_bugfix_id, $skip_patch_type) = @$skip_bb_rec;
     last if (($skip_patch_type  eq "") &&
             ($skip_base_bug ne $skip_backport_bug));
   }

   if($skip_aru ne $aru_obj->{aru})
   {
    my $msg ;

    $log_fh->print("\nUpdating Skip bug : $skip_backport_bug \n");

    $msg = "ARU $skip_aru was initially included through snowball ".
           "in ARU $superset_aru but ARU $superset_aru was also skipped . "
                      if($superset_aru ne $aru_obj->{aru});
    $msg .= "ARU $superset_aru is finally included through snowball ".
            "in Superset ARU " . $aru_obj->{aru} . ".";

    if($build_status == 1)
    {
     $msg .= " Superset ARU " . $aru_obj->{aru} .
             " has finished successfully ";
    }
    else
    {
     $msg .= " Build for Superset ARU " . $aru_obj->{aru} .
             " has failed ";
    }
    ARUDB::exec_sp('bugdb.async_create_bug_text', $skip_backport_bug, $msg);
   }
  }
}

sub  get_branched_farm_req_info
{
  my ($self) = @_;
  my $object = ARUDB::query_object('GET_BRANCHED_FARM_REQUESTS',
                                   $self->{request_id});
  my @result = $object->all_rows();

  my $count = scalar(@result);

  if ($count == 0)
  {
      my $bugfix_request_id = $self->{bugfix_request_id};

      $object = ARUDB::query_object('GET_BRANCHED_FARM_AUTO_REQUESTS',
                                    $self->{request_id},$bugfix_request_id);
      @result = $object->all_rows();
  }

  my (%ret,$prev_build_type);
  foreach my $elem(@result)
  {
      my ($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                                                 $elem->[0]);
      my %params;
      foreach my $i (split('!',$req_params))
      {
          my ($key, $value) = split(':',$i);
          $params{lc($key)} = $value;
      }
      $ret{$params{build_type}} = \%params
          if($params{build_type} ne $prev_build_type);
      $prev_build_type = $params{build_type};
  }

  return \%ret;
}

sub release
{
    my ($self, $aru_no, $pse, $version) = @_;

    my $log_fh = $self->{log_fh} || $self->{params}->{log_fh}
                                 || $self->{aru_log};
    my $bug_progmmer = 'PATCHQ';

    my $aru_obj = ARU::BugfixRequest->new($aru_no);
    $aru_obj->get_details();

    my $orch_ref =
            APF::PBuild::OrchestrateAPF->new({request_id  => $self->{request_id},
                                              log_fh      => $log_fh,
                                              pse         => $pse});

    $orch_ref->{aru_obj} = $aru_obj;
    $orch_ref->{utility_version} = $version || $aru_obj->{release};

    my $is_fmw12c = $orch_ref->is_fmw12c();
    if ($is_fmw12c)
    {
        $log_fh->print("DEBUG: Posting the data to HUDSON".
                       "about the job \n");

        $orch_ref->post_fmw12c_data($pse, "test_status",
                                    $self->{request_id});

    }

    $log_fh->print("Releasing $aru_no (PSE: $pse, $version) \n");

    #
    #  if autoport, Set the patch status to  fixftp internal
    #
    my ($patch_request) = ARUDB::single_row_query("GET_PSE_BUG_NO",
                                                  $aru_no);

    my $auto_obj = APF::PBuild::AutoPort->new({aru => $aru_no,
                                               request_id =>
                                               $self->{request_id},
                                               log_fh => $self->{aru_log},});
    if ($self->{testmanual})
    {
        $patch_request = $pse;
    }

    if ($self->{testmanual} && $orch_ref->is_rdbms($pse) && 
        (defined($self->{is_bundle_patch})) && ($self->{is_bundle_patch} == 1))
    {
        $log_fh->print("This is a manually uploaded RDBMS bundle patch.");
        $log_fh->print(" Hence keeping it it patch ftpd to Dev\n");
        $log_fh->print("ARU: $aru_no, Status: Ftpd to Development... \n");
 
        #
        # Update the comments for this ARU
        #
        ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                       ARU::Const::patch_ftped_dev, "",
                       ARU::Const::apf2_userid,
                       'This is a manually uploaded RDBMS bundle patch. Hence ftping only to patch ftpd to Dev. Install Test Succeeded');
        $self->_update_bug($pse, {status        => 93,
                                  programmer    => 'PATCHQ',
                                  test_name     => 'APF-INSTALLTEST-RESULTS-SUCCESS',
                                  tag_name     => 'APF-INSTALLTEST-RESULTS-SUCCESS',
                                  version_fixed => $version,
                                  body => "This is a manually uploaded RDBMS bundle patch. Hence Keeping it in patch ftpd to Dev."});
    }
    elsif (!$patch_request)
    {
        print STDOUT "ARU: $aru_no, Status:internal  ...\n";

        #
        # Update the comments for this ARU
        #
        ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                       ARU::Const::patch_ftped_internal, "",
                       ARU::Const::apf2_userid,
                       'Auto Port Install Test succeeded');
        #
        # Check whether this autoport is requested when the txn is closed
        # Ref bug:11811966
        #
        my ($count) = ARUDB::single_column_query("GET_AUTOPORT_PSES",
                                                 $aru_no,'O');

        if ($aru_obj->{platform_id} eq ARU::Const::platform_linux
            && !($count))
        {
            $log_fh->print("Request Auto Port: $aru_no \n");

            #
            # Request other auto port patches
            #
            $auto_obj->request_auto_port($aru_no);
        }
    }
    elsif (exists ($self->{is_a_cloud_patch}) && $self->{is_a_cloud_patch} == 1) {
        print STDOUT "ARU: $aru_no, Status:internal  ...\n";

        #
        # Update the comments for this ARU
        #
        ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                       ARU::Const::patch_ftped_internal, "",
                       ARU::Const::apf2_userid,
                       'It is a cloud patch. Hence ftping only to internal');
    }
    else
    {
        $log_fh->print("Patch applied successfully, $patch_request \n");

        #
        # Patch applied successfully
        #
        $pse            = $patch_request;
        my $platform_id = $aru_obj->{platform_id};
        my $status = 93;

        my $upd_text  = "Patch built for $version ARU $aru_no and applied " .
            "successfully.";

        my $has_dynamic_do = ARUDB::exec_sf('aru.pbuild.has_dynamic_do',
                                            $aru_no);

        my ($blr_base_bug) =
            ARUDB::single_row_query('GET_BASEBUG_FOR_PSE', $pse);

        my ($blr_gen_port) =
            ARUDB::single_row_query('GET_GENERIC_OR_PORT_SPECIFIC',
                                    $blr_base_bug);

        $log_fh->print("\n P1 PSE Request: Base bug: $blr_base_bug ".
                       "Base bug G/P: $blr_gen_port \n");

        my ($blr_bug);

        if ($blr_gen_port eq 'M')
        {
            $blr_bug = $blr_base_bug;
            $log_fh->print("BLRBug: $blr_bug \n");
        }
        else
        {
            #
            # Get the bug details using the aru backport requests
            #
            my ($base_bug_p1) = ARUDB::single_row_query("GET_BASEBUG_FOR_PSE",
                                                        $pse);

           #  ($base_bug_p1, $version_id_p1, $platform_id_p1,
#              $release_name_p1) =
#                  ARUDB::single_row_query
#                          ("GET_BUG_DET_FROM_BACKPORT_REQUESTS",
#                           $pse,
#                           ARU::Const::backport_pse);

            $log_fh->print("Base Bug P1: $base_bug_p1 \n");

            # if ((defined $platform_id_p1) || $platform_id_p1 ne "")
#             {
                #
                # Getting the BLR number using the PSE and CPCT release id
                #
                # ($blr_bug) = ARUDB::single_row_query
#                     ("GET_BLR_FROM_PSE_STATUS",
#                      $base_bug_p1,
#                      $version_id_p1,
#                      ARU::Const::backport_blr,
#                      ARU::Const::backport_mlr,
#                      ARU::Const::backport_request_bug_filed);

                my ($pse_version) = ARUDB::single_row_query("GET_UTILITY_VERSION",
                                                            $pse);
                my $raise_exception = "y";
                my $ignore_blr_status = "y";

                $blr_bug  = ARUDB::exec_sf('aru.bugdb.get_blr_bug',
                                           $base_bug_p1, $pse_version,
                                           ['boolean',$raise_exception],
                                           $aru_obj->{product_id},
                                           ['boolean',$ignore_blr_status]);


                $log_fh->print("DEBUG: BLR Bug1: $blr_bug \n");
            #}
        }

        $log_fh->print("BLR Bug details: $blr_bug \n");
        if ($orch_ref->is_rdbms($pse) &&
            !(defined($self->{is_bundle_patch} && ($self->{is_bundle_patch} == 1))))
        {
            my $trans_list = ARUDB::exec_sf('aru.pbuild.get_blr_transaction_name',
                                            $blr_bug);

            my @transaction_names     = split('!',$trans_list);
            $self->{transaction_name} = $transaction_names[0];

            $self->{log_fh}->print("DEBUG: Transaction Name : ".
                                   "$self->{transaction_name} \n");
        }

        my $p1_blr_pse_request = 0;
        my ($blr_status, $blr_prod_id, $blr_priority);

        if ((defined $blr_bug) && $blr_bug ne "")
        {
            ($blr_status, $blr_prod_id, $blr_priority) =
                ARUDB::single_row_query("GET_BUG_DETAILS_FROM_BUGDB",
                                        $blr_bug);

            $blr_prod_id =~ s/\s//g;
            $blr_status =~ s/\s//g;
            $blr_priority =~ s/\s//g;
            my ($req_enabled) = ARUDB::single_row_query("GET_COMPAT_PARAM",
                                               'P1_PSE_EXCEPTION_PRODUCT');

            $log_fh->print("\nRequest Enabled for $req_enabled, ".
                           "$blr_priority, $blr_status, ".
                           "$blr_prod_id .\n");

            if ($req_enabled =~ /$blr_prod_id/ &&
                $blr_priority == 1 && $blr_status == 11)
            {
                $p1_blr_pse_request = 1;
            }

            $log_fh->print("P1 BLR PSE Request: $p1_blr_pse_request \n");
        }

        my $do_release_patch = 0;
        $orch_ref->{product_id} = $aru_obj->{product_id};
        $orch_ref->{release_id} = $aru_obj->{release_id};
        $orch_ref->is_parallel_proc_enabled();
        my $values_defined = 0;
        if ($orch_ref->{enabled} == 1)
        {
            $log_fh->print("DEBUG: Parallel processing is enabled : $pse\n");
            my ($p_severity)  = ARUDB::single_row_query("GET_BACKPORT_SEVERITY",
                                                        $pse);

            if (!($orch_ref->{only_p1} == 1 && $p_severity > 1))
            {
                $log_fh->print("DEBUG: BLR Status : $blr_status\n");
                if ($blr_status == 35)
                {
                    $do_release_patch = 1;
                }

                if ($do_release_patch == 0)
                {
                    $log_fh->print("DEBUG: Updating the bug to 40/PSEREP \n");
                    $upd_text.= "This patch built for the P1 BLR/MLR\n".
                        "The patch will be released once the BLR/MLR is closed\n".
                            PB::Config::se_man_validation_url;
                    $status = 40;
                    $bug_progmmer = 'PSEREP';
                    $self->{do_not_override_prog} = 1;
                    $values_defined = 1;
                }
            }
        }

        if ($orch_ref->is_fix_control_files_enabled($version,
                                                    $self->{transaction_name}) == 1)
        {
            $upd_text.= "This patch contains fix control files".
                "\n Please verify the patch manually .\n".
                    "Instructions for SE can be found here\n".
                        APF::Config::se_man_validation_url;
            $status = 52;
            $self->{additional_tags} = 'APF_FIX_CONTROL_REVIEW';
        }
        elsif ($has_dynamic_do && $values_defined == 0 )
        {
            $upd_text.= "This patch contains DOs seeded dynamically by ".
                "APF.\n Please verify the patch manually .\n".
                    "Instructions for SE can be found here\n".
                        APF::Config::se_man_validation_url;
            $status = 52;
        }
        elsif ($p1_blr_pse_request == 1 && $values_defined == 0)
        {
            $upd_text.= "This patch built for the P1 BLR/MLR\n".
                "The patch will be released once the BLR/MLR is closed\n".
                      PB::Config::se_man_validation_url;
            $status = 52;
        }
        else
        {
            if ((($values_defined == 0) ||($do_release_patch == 1)) && 
                !($version =~ /^5\.5/ && $aru_obj->{product_id} == 14667)) 
            {
                $log_fh->print("Release $aru_no, $upd_text \n");
                ARUDB::exec_sp("pbuild.release", $aru_no, $upd_text);
            }
        }

        #
        # Issuing a sleep for 2 sec as the updating aru and this bugdb
        # call isd_request clashing.
        #
        sleep(2);

        #
        # Update the bugdb.  Note that all finished bugs go to PATCHQ.
        #
        my $additional_tags = $self->{additional_tags} || "";

        my $tag_name = "$additional_tags APF";
        $tag_name = "$self->{emcc_tag} $additional_tags APF"
            if ($self->{emcc_installtest});

        #
        # Remove leading space and multiple with single
        #
        $tag_name =~ s/^\s+//;
        $tag_name =~ s/ +/ /g;

        $log_fh->print("version = $version product_id = $aru_obj->{product_id}\n");
        if($version =~ /^5\.5/ && ($aru_obj->{product_id} == 14667 || $aru_obj->{product_id} == 11903))
        {
            $bug_progmmer = APF::Config::oas_jenkins_bi_triagee; 
            $status         = 52;
        }
        $self->_update_bug($pse, {status        => $status,
                                  programmer    => $bug_progmmer,
                                  test_name     => 'APF',
                                  tag_name      => $tag_name,
                                  version_fixed => $version,
                                  body          => $upd_text}); 

        #
        # Request other auto port patches
        #
        $auto_obj->request_auto_port($aru_no,$pse)
            if ($auto_obj->is_autoport_enabled($pse));
    }

    if ($is_fmw12c)
    {
        $orch_ref->post_fmw12c_data($pse, "release_status",
                                    $self->{request_id});
    }
}



sub release_fusion
{
    my ($self, $aru_no, $bug, $version, $aru_obj) = @_;

    #
    # Update the bugdb. Note that all finished bugs go to PATCHQ.
    #
    $self->_update_bug($bug, {status        => 93,
                              programmer    => 'PATCHQ',
                              test_name     => 'APF',
                              version_fixed => $version,
                body =>  "ARU $aru_no completed for ".
                         $aru_obj->{platform} . "."})
                if ($aru_obj->{language_id} == ARU::Const::language_US);

    #
    # fusion patch base bug should be on generic(289) or linux 64(226)
    #
    my $auto_obj = APF::PBuild::AutoPort->new({aru => $aru_no,
                                               request_id =>
                                               $self->{request_id},
                                               prod_fam_id =>
                                               $self->{prod_fam_id},
                                               log_fh => $self->{aru_log}
                                              });
    # bug 20119291
    my ($requires_porting) =
             ARUDB::single_row_query('GET_BUGFIX_REQUIRES_PORTING_FLAG',
                                     $aru_obj->{bugfix_id},
                                     $aru_obj->{release_id});
     $self->{requires_porting} = "Y"
         if ($self->{requires_porting} ne "Y" and $requires_porting eq "Y");

    $auto_obj->request_auto_port($aru_no,$bug)
        if($self->{requires_porting} eq "Y" &&
           $aru_obj->{language_id} == ARU::Const::language_US &&
           ( $aru_obj->{platform_id} == ARU::Const::platform_generic ||
             $aru_obj->{platform_id} == ARU::Const::platform_linux64_amd
           )
           );

}



sub check_install_test_farm_status
{

    my ($self,$pse,$it,$aru_no,$version) = @_;

    my $log_fh = $self->{aru_log};
    my $farm_params = $self->get_branched_farm_req_info();


    my $is_system_patch = 0;  #DISABLE_SYSTEM_PATCH
    eval {
        $is_system_patch =   ARUDB::exec_sf_boolean('apf_system_patch_detail.is_system_patch_series_trk_bug',
                             $it->{aru_obj}->{bug});
    };
    if ($@)
    {
        $is_system_patch = 0;
    }
    if( scalar(keys %$farm_params) )
    {
        my $suc = 1;
        my %failed_info;

        foreach my $build_type(sort keys %$farm_params)
        {
            my $par_ref = $farm_params->{$build_type};
            unless($par_ref->{suc})
            {
                $suc = 0;
                $failed_info{$build_type}{transaction_name} =
                    $par_ref->{transaction_name};
                $failed_info{$build_type}{log_loc} =
                    $par_ref->{log_loc};
            }
        }

        # The system patches should be released only after the basic install
        # test is complete. Hence this code is added.

        $log_fh->print( "TAB_TEST_TYPE:$it->{req_params}->{tab_test_type}, $it->{req_params}->{status}\n");
        if ( $is_system_patch == 1 &&
           (!(defined($it->{req_params}->{status}))) &&
            $it->{req_params}->{tab_test_type} eq "B")
        {
            ARUDB::exec_sp("apf_queue.update_aru",
                           $aru_no,
                           ARU::Const::patch_ftped_internal,
                           'Waiting on Basic TAB testing Completion');

            $self->_update_bug($pse, {status        => 52,
                                     programmer    => 'PATCHQ',
                                     test_name     => 'APF-TAB(BASIC)-INSTALLTEST-SUBMITTED',
                                     tag_name     => 'APF-TAB(BASIC)-INSTALLTEST-SUBMITTED',
                                     body => "The request is successfully submitted " .
                                     "to TAB (Basic). "});
        }
        elsif ( $is_system_patch == 1 &&
           (defined($it->{req_params}->{status})) &&
            $it->{req_params}->{status} eq "fail" &&
            $it->{req_params}->{tab_test_type} eq "B")
        {
            ARUDB::exec_sp("apf_queue.update_aru",
                           $aru_no,
                           ARU::Const::patch_ftped_internal,
                           "Install Test failed in TAB (BASIC)" .
                          " See log files for more details.");

            $self->_update_bug($pse, {status        => 52,
                                     programmer    => 'PATCHQ',
                                     test_name     => 'APF-TAB(BASIC)-INSTALLTEST-RESULTS-FAIL',
                                     tag_name     => 'APF-TAB(BASIC)-INSTALLTEST-RESULTS-FAIL',
                                     body => "This PSE is being reviewed and " .
                                     "queued for manual processing.  Requestor " .
                                     "please contact a Database Fixdelivery representative if this " .
                                     "patch request requires urgent attention.\n" .
				     "Fixed Delivery Esclation process\n" .
				     "(https://confluence.oraclecorp.com/confluence/display/SE/Fix+Delivery+%3A+Escalation+Process)"});

        }
        elsif ( $it->skip_farm()  || $suc )
        {
            $self->release($aru_no,$pse,$version);
        }
        else
        {
            print STDOUT "ARU: $aru_no, Status: internal = \n";

            ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                           ARU::Const::patch_ftped_internal,
                           "", ARU::Const::apf2_userid,
                           "Install test succeeded");

            my $aru_link = "http://".APF::Config::url_host_port.
                "/ARU/ViewPatchRequest/process_form?aru=".
                    $aru_no;

            my  $bug_body = "This patch needs to be manually ".
                "validated by SE to confirm the test ".
                    "results.\n";
            foreach my $build_type(sort keys %failed_info)
            {
                $bug_body.=  "Transaction name in ADE : ";
                $bug_body.=  "( $build_type )"
                    if(scalar(keys %failed_info) > 1);
                $bug_body.=
                    $failed_info{$build_type}{transaction_name};
                $bug_body.= "\n";

                $bug_body.=  "Path to farm results : ";
                $bug_body.=  "( $build_type )"
                    if(scalar(keys %failed_info) > 1);
                $bug_body.=
                    $failed_info{$build_type}{log_loc};
                $bug_body.= "\n";
            }

            $bug_body.= "Link to patch on ARU: $aru_link \n".
                "Instructions for SE can be found here\n".
                    APF::Config::se_man_validation_url;

            $self->_update_bug($pse, {status  => 52,
                                      programmer    => 'PATCHQ',
                                      test_name     => 'APF',
                                      version_fixed => $version,
                                      body =>  $bug_body});

        }
    }
    else
    {

      $self->{additional_tags} = "APF-SQL-AUTO-RELEASED"
        if (($it->{sql_files} == 1) && ($it->{sql_auto_release} == 1));

         my $comp_install_enabled = 0;
         eval
         {
            ($comp_install_enabled) = ARUDB::exec_sf(
                'aru_parameter.get_parameter_value', 'COMP_INST_ENABLED');
         };

         if($@)
         {
             $self->{log_fh}->print("\nComprehensive installtest flag is not set. ".
                                    "Will default to comprehensive test disabled mode\n");
         }
        $log_fh->print("DEBUG_SYSPATCH: System patch :$is_system_patch , $it->{req_params}->{status} , $it->{req_params}->{tab_test_type} \n");
        if ( $is_system_patch == 1 &&
           (!($it->{req_params}->{status})) &&
           $it->{req_params}->{tab_test_type} eq "B")
        {
            $log_fh->print("DEBUG_SYSPATCH3");

            $self->_update_bug($pse, {test_name     => 'APF-TAB(BASIC)-INSTALLTEST-SUBMITTED',
                                      tag_name      => 'APF-TAB(BASIC)-INSTALLTEST-SUBMITTED',
                                      body => "The request is successfully submitted " .
                                      "to TAB (Basic). "});
        }
        elsif ( $is_system_patch == 1 &&
           (defined($it->{req_params}->{status})) &&
            $it->{req_params}->{tab_test_type} eq "B" &&
            $it->{req_params}->{status} eq "fail" )
        {
            ARUDB::exec_sp("apf_queue.update_aru",
                           $aru_no,
                           ARU::Const::patch_ftped_internal,
                           "Install Test failed in TAB (Basic)" .
                          " See log files for more details.");

            $self->_update_bug($pse, {status        => 52,
                                     programmer    => 'PATCHQ',
                                     test_name     => 'APF-TAB(BASIC)-INSTALLTEST-RESULTS-FAIL',
                                     tag_name     => 'APF-TAB(BASIC)-INSTALLTEST-RESULTS-FAIL',
                                     body => "This PSE is being reviewed and " .
                                     "queued for manual processing.  Requestor " .
                                     "please contact a Database Fixdelivery representative if this " .
                                     "patch request requires urgent attention.\n" .
				     "Fixed Delivery Esclation process\n" .
				     "(https://confluence.oraclecorp.com/confluence/display/SE/Fix+Delivery+%3A+Escalation+Process)"});

        }
        elsif ( $is_system_patch == 1 &&
           (!($it->{req_params}->{status})) &&
           $it->{req_params}->{tab_test_type} eq "C")
        {
            if ($comp_install_enabled == 0) {
                ARUDB::exec_sp("apf_queue.update_aru",
                               $aru_no,
                               ARU::Const::patch_ftped_dev,
                               "Install Test TAB (Basic) is successful and comprehensive installtest is disabled." .
                               " Hence moving the patch to ftped to Dev for further testing/certification.");
                $self->_update_bug($pse, { status        => 93,
                                           programmer    => 'PATCHQ',
                                           test_name     => 'APF',
                                           tag_name      => 'APF',
                                           version_fixed => $version,
                                           body          => "TAB (Comprehensive is disabled). Hence closing the PSE processing" .
                                                               " with Basic installtest. "});
            }
            elsif((defined($it->{req_params}->{tab_completed}))
                   && $it->{req_params}->{tab_completed} == 1) {
                ARUDB::exec_sp("apf_queue.update_aru",
                               $aru_no,
                               ARU::Const::patch_ftped_dev,
                               "Install Test TAB (Comprehensive) is successful.");

                $self->_update_bug($pse, { status        => 93,
                                           programmer    => 'PATCHQ',
                                           test_name     => 'APF',
                                           tag_name      => 'APF',
                                           version_fixed => $version,
                                           body          => "TAB Comprehensive installtest is complete. Hence closing the PSE"
                                                            });
            }
            else {
                ARUDB::exec_sp("apf_queue.update_aru",
                               $aru_no,
                               ARU::Const::patch_ftped_dev,
                               "Install Test TAB (Basic) is successful. Triggering comprehensive installtest" .
                               " and moving the patch to ftped to Dev for further testing/certification.");
                $self->_update_bug($pse, {test_name     => 'APF-TAB(COMPREHENSIVE)-INSTALLTEST-SUBMITTED',
                                          tag_name      => 'APF-TAB(COMPREHENSIVE)-INSTALLTEST-SUBMITTED',
                                          body => "The request is successfully submitted " .
                                          "to TAB (Comprehensive). "});
            }
        }
        elsif ( $is_system_patch == 1 &&
           (defined($it->{req_params}->{status})) &&
            $it->{req_params}->{status} eq "fail" )
        {
            $log_fh->print("DEBUG_SYSPATCH4");
            ARUDB::exec_sp("apf_queue.update_aru",
                           $aru_no,
                           ARU::Const::patch_ftped_internal,
                           "Install Test failed in TAB (Comprehensive)" .
                          " See log files for more details.");

            $self->_update_bug($pse, {status        => 52,
                                     programmer    => 'PATCHQ',
                                     test_name     => 'APF-TAB(COMPREHENSIVE)-INSTALLTEST-RESULTS-FAIL',
                                     tag_name     => 'APF-TAB(COMPREHENSIVE)-INSTALLTEST-RESULTS-FAIL',
                                     body => "This PSE is being reviewed and " .
                                     "queued for manual processing.  Requestor " .
                                     "please contact a Fixed Delivery Esclation process representative if this " .
                                     "patch request requires urgent attention.\n" .
				     "Fixed Delivery Esclation process\n" .
				     "(https://confluence.oraclecorp.com/confluence/display/SE/Fix+Delivery+%3A+Escalation+Process)"});

        }
        else {
         $self->release($aru_no,$pse,$version);
        }
    }

}


sub set_ade_okinit_info
{
    my $host_name = PB::Config::short_host;
    my $log_file  = "$ENV{ISD_HOME}/log/pbuild_" . $host_name .
                    "_ade_okinit_info.log";

    my $log_fh    = new FileHandle(">> $log_file");

    my $ade_hosts = PB::Config::ade_krb_info;

    $ade_hosts ||= [];

    foreach my $host_info (@$ade_hosts)
    {
        SrcCtl::ADEUtil::verify_and_set_krb_ticket($log_fh,
                                                   split(":", $host_info));
    }

    $log_fh->close();
}


sub get_base_bug_owner
{
    my ($self, $bug, $backport_test_name, $is_fmw12c, $aru_release_id) = @_;

    my ($bugdb_id, $status, $assignee_id, $ignore_cpm);

    $ignore_cpm = 0;
    ARUDB::exec_sp("bugdb.get_bug_status", $bug, \$status);

    #
    # just return if backport is already closed.
    # check bug 14805338 for details.
    #
    if ($status == 35)
    {
        my ($assignee, $stat) =
              ARUDB::single_row_query('GET_DEFAULT_ASSIGNEE',
                                      $bug);

        my ($copy_merge) = ARUDB::single_row_query('GET_COPY_OR_MERGE',
                                                   $bug);

        $self->{copy_merge} = $copy_merge;
        return ($assignee, 35);
    }
    if ($backport_test_name eq 'APF-INCORRECTLY-RETRIED') {
        return ("SUNREP",35);
    }

    if ($backport_test_name eq "APF-USER-ABORTED")
    {
        return ("SUNREP", 53);
    }

    my ($abstract, $category, $gen_or_port, $priority, $port_id, $prod_id);

    ARUDB::exec_sp("bugdb.get_bug_info",
                   $bug, \$abstract, \$category, \$gen_or_port,
                   \$priority, \$port_id, \$prod_id);

    my $cpm_prod_ids = ARUDB::exec_sf(
                       'aru_parameter.get_parameter_value',
                       'BACKPORTS');

    my @cpm_prod_array = split(/,/, $cpm_prod_ids);
    foreach my $t_prod_id (@cpm_prod_array)
    {
        if ($prod_id == $t_prod_id)
        {
            my ($assignee, $stat) =
              ARUDB::single_row_query('GET_DEFAULT_ASSIGNEE', $bug);
            return ($assignee, 51);
        }
    }

    $status = 11;

    my $assginee_dev = 1;
    my $count = 1;

    # bug-30030368
    my ($str) = ARUDB::exec_sf('apf_build_request.getAssignee', $bug);

    if ($str ne "")
    {
        ($assignee_id, $status) = split(':', $str);
        $bugdb_id = $assignee_id;
    }
    else
    {
        if ($gen_or_port eq "Z")
        {
            #
            # Check the CPM rule, whether CI should be assigned to developer
            # or default queue
            #
            ($assginee_dev) = ARUDB::single_row_query('CI_ASSIGNED_TO_DEV',
                                                         $bug);

            $self->{log_fh}->print("\nAssign to Developer: $assginee_dev\n");
            if ($assginee_dev == 0)
            {
                ($assignee_id, $status) = ARUDB::single_row_query(
                                           'GET_DEFAULT_ASSIGNEE', $bug);
                $self->{log_fh}->print("\nAssigning to $assignee_id in " .
                                       "status $status\n");
                $count = 1;
            }
        }

        if ($assginee_dev == 1)
        {
            ($bugdb_id) = ARUDB::single_row_query('GET_BASE_BUG_ASSIGNEE', $bug);
            $assignee_id = $bugdb_id;

            ($count) = ARUDB::single_row_query('IS_BUGDB_ID_VALID',
                                               $bugdb_id);
        }

        if ($count != 1)
        {
            ($bugdb_id, $status) = ARUDB::single_row_query(
                                    'GET_DEFAULT_ASSIGNEE', $bug);
            $assignee_id = $bugdb_id;
            $status = 51;


            my @bug_text;

            push (@bug_text, ".");
            push (@bug_text, "Assigning backport to area queue since");

            if ($count > 1)
            {
                push (@bug_text, "APF got multiple records from Bug database.");
            }
            else
            {
                push (@bug_text, "APF could not get BugDB id from Bug database.");
            }

            foreach my $text (@bug_text)
            {
                my @params = (
                             { name => 'pn_bugno',
                               data => $bug},
                             { name => 'pv_text',
                               data => $text});

                ARUDB::exec_sp("bugdb.create_bug_text",
                               @params);
            }
        }
    }

    $self->{log_fh} =  $self->{log_fh} ||$self->{aru_log};

    $self->{log_fh}->print("\nBug: $bug, Priority: $priority, G/P: " .
                           "$gen_or_port, Testname: $backport_test_name\n");

    my $old_status = $status;

    #
    # ER-32376964 directly assign to developer
    #
    my $devAssign = "";
    eval
    {
        ($devAssign) = ARUDB::exec_sf(
                              'aru_parameter.get_parameter_value',
                              'ASSIGN_BACKPORTS_TO_DEV');
    };

    if ($devAssign ne "")
    {
        my ($version) = ARUDB::single_row_query(
                        'GET_UTILITY_VERSION', $bug);

        my @devArray = split(',', $devAssign);
        foreach my $d (@devArray)
        {
            my ($type, $rel) = split(':', $d);

            if ($gen_or_port eq $type && $rel eq $version)
            {
                return ($assignee_id, $status, 1);
            }
        }
    }

    # 
    # See bug-32850719 for details
    #
    my $triageAssign = 1;

    if ($priority == 1)
    {
        my $pOneAssignment = 0;
        eval
        {
            ($pOneAssignment) = ARUDB::exec_sf('aru_parameter.get_parameter_value', 'BACKPORT_P1_ASSIGNMENT');
        };

        $triageAssign = ($pOneAssignment == 1) ? 1 : 0;
    };

    if ($triageAssign == 1)
    {
        my $triage_queue = 0;

        $self->{log_fh}->print("Applying new backport assignment logic\n");

        $triage_queue = 1;

        my ($dev_codes) = ARUDB::exec_sf(
                          'aru_parameter.get_parameter_value',
                          'BACKPORTS_TO_BE_ASSIGNED_TO_DEV');

        my ($dev_codes_1) = ARUDB::exec_sf(
                            'aru_parameter.get_parameter_value',
                            'BACKPORTS_TO_BE_ASSIGNED_TO_DEV_1');

        $dev_codes = $dev_codes . "," .$dev_codes_1;

        eval{
           my ($dev_prod_codes) = ARUDB::exec_sf(
                                  'aru_parameter.get_parameter_value',
                                  'BACKPORTS_'.$prod_id.'_TO_BE_ASSIGNED_TO_DEV');
           $dev_codes = $dev_codes . "," .$dev_prod_codes;
        };

        foreach my $test_name (split (/,/, $dev_codes))
        {
            if ($test_name eq $backport_test_name)
            {
                $triage_queue = 0;
                last;
            }
        }

        if($is_fmw12c)
        {
            $triage_queue = 0;
        }

        if ($triage_queue == 1)
        {
            $bugdb_id = 'BKPTRGQ';
            $status   = 51;
        }

        if ($triage_queue == 1)
        {
            my $text = "Instructions for SE managers";
            my @params = (
                         { name => 'pn_bugno',
                           data => $bug},
                         { name => 'pv_text',
                           data => $text});

            ARUDB::exec_sp("bugdb.create_bug_text",
                           @params);

            $text = "----------------------------";
            @params = (
                         { name => 'pn_bugno',
                           data => $bug},
                         { name => 'pv_text',
                           data => $text});

            ARUDB::exec_sp("bugdb.create_bug_text",
                           @params);

            $text = "Currently backport is in triaging queue, " .
                       "if you need this";

            @params = (
                         { name => 'pn_bugno',
                           data => $bug},
                         { name => 'pv_text',
                           data => $text});

            ARUDB::exec_sp("bugdb.create_bug_text",
                           @params);

            $text = "backport urgently, please assign it to " .
                    "$old_status/$assignee_id";

            @params = (
                         { name => 'pn_bugno',
                           data => $bug},
                         { name => 'pv_text',
                           data => $text});

            ARUDB::exec_sp("bugdb.create_bug_text",
                           @params);
        }
        else
        {
            #
            # Check special assignment case
            #
            my $assign_logic = "";
            my $bugdb_id_org = $bugdb_id;
            my $status_org   = $status;
            my $found        = 0;

            my ($version) = ARUDB::single_row_query(
                            'GET_UTILITY_VERSION', $bug);

            $self->{log_fh}->print("\n\n");
            #
            # Exception where CI should be assigned to default assignee
            # either base bug owner and/or default queue
            #
            eval
            {
                $self->{log_fh}->print("\nChecking exception case for $backport_test_name...");
                my $param_name = $backport_test_name . "_EXCEPTION";
                ($assign_logic) = ARUDB::exec_sf(
                'aru_parameter.get_parameter_value', $param_name);
            };

            if ($assign_logic ne "")
            {
                my @array = split(/!/, $assign_logic);
                foreach my $d (@array)
                {
                    my ($rel_type, $bug_type) = split(/:/, $d);

                    if ($version =~ /$rel_type$/ && $gen_or_port eq $bug_type)
                    {
                        $self->{log_fh}->print("\nFound exception case $backport_test_name, returning...");
                        $bugdb_id = $bugdb_id_org;
                        $status = $status_org;
                        $ignore_cpm = 0;
                        $found = 1;
                        last;
                    }
                }
            }

            return ($bugdb_id, $status, $ignore_cpm)
                if ($found == 1);

            $assign_logic = "";
            $found        = 0;

            #
            # Exception where CI should be assigned to SUNREP
            #
            $assign_logic = "";
            eval
            {
                $self->{log_fh}->print("\nChecking exception case for $backport_test_name...");
                my $param_name = $backport_test_name . "_ASSIGNMENT_EXCEPTION";
                ($assign_logic) = ARUDB::exec_sf(
                'aru_parameter.get_parameter_value', $param_name);
            };

            if ($assign_logic ne "")
            {
                my @array = split(/!/, $assign_logic);
                foreach my $d (@array)
                {
                    my ($rel_type, $bug_type, $stat, $assignee) = split(/:/, $d);

                    if ($version =~ /$rel_type$/ && $gen_or_port eq $bug_type)
                    {
                        $self->{log_fh}->print("\nFound exception case $backport_test_name, returning...");
                        $bugdb_id = $assignee;
                        $status = $stat;
                        $ignore_cpm = 1;
                        $found = 1;
                        last;
                    }
                }
            }
            return ($bugdb_id, $status, $ignore_cpm)
                if ($found == 1);

            $assign_logic = "";
            $found        = 0;


            ############################################################################################################################
            # ER: 33809839 - Assignee should be CIREPQ for backports filed on base release and failing with APF-FARM-REGRESSION-HANDOVER
            ############################################################################################################################

            my $current_release_id = $aru_release_id;
            my $base_release_id = ARUDB::single_row_query('GET_BASE_RELEASE_ID',
                                        $aru_release_id);

            $self->{log_fh}->print("\nRelease ID: $current_release_id\n");
	    $self->{log_fh}->print("\nBase Release ID: $base_release_id\n");
            $self->{log_fh}->print("\nActual Utility Version: $version\n");
             
            if ($current_release_id == $base_release_id)
	    {
		$version .= "DBRU";
                $self->{log_fh}->print("\nModified Utility Version: $version\n");
            }       

            #
            # Exception where CI should be assigned to CIREPQ
            #
            eval
            {
                $self->{log_fh}->print("\nChecking exception case for $backport_test_name...");
                my $param_name = $backport_test_name . "_ASSIGNMENT";
                ($assign_logic) = ARUDB::exec_sf('aru_parameter.get_parameter_value', $param_name);

                #
                # Exceptional case for APF-FARM-REGRESSIONS-HANDOVER
                #
                if($assign_logic ne "" && $backport_test_name eq "APF-FARM-REGRESSIONS-HANDOVER")
                {
                    my ($filteredTxnDiffResult) = ARUDB::exec_sf(
                        'apf_build_request.getFarmNullTxnFilterDiffSummary',
                        $self->{backport_bug});

                   $self->{log_fh}->print("\nNull txn diffs: -$filteredTxnDiffResult-...");
                   #
                   # For Actual Txn diffs, assign to developer insted of CIREPQ
                   # or developer submitted lrgs should go back to developer
                   #
                   if($filteredTxnDiffResult eq 'NULL_TXN_ZERO_DIFF' ||
                      $filteredTxnDiffResult eq 'DEV_SUBMITTED_LRGS')
                   {
                       $assign_logic = "";
                   }             
                }
            };

            if ($assign_logic ne "")
            {
                my @array = split(/!/, $assign_logic);
                foreach my $d (@array)
                {
                    my ($rel_type, $bug_type, $stat, $assignee) = split(/:/, $d);

                    if ($version =~ /$rel_type$/ && $gen_or_port eq $bug_type)
                    {
                        $self->{log_fh}->print("\nFound exception case $backport_test_name, returning...");
                        $bugdb_id = $assignee;
                        $status = $stat;
                        $ignore_cpm = 1;
                        last;
                    }
                }
            }
        }
        # This is at incorrect place causing compilation error. This needs
        # to be reviewed before adding back
        #else #32930821
        #{
        #    $self->send_alert_on_P1_BLR_failure($bugdb_id, $bug,$self->{base_bug},$self->{bugdb_err_msg},$count)
        #      if (($gen_or_port eq "B") && ($priority == 1) && (ConfigLoader::runtime("production")));
        #}
    }
     

    $self->send_backport_failure_alert($bugdb_id, $bug, $self->{base_bug},
           $self->{bugdb_err_msg}, $backport_test_name);

    return ($bugdb_id, $status, $ignore_cpm);
}

sub send_backport_failure_alert
{
    my ($self, $bugdb_id, $backport_bug, $base_bug, $err_msg, $test_name) = @_;

    my $preprocess = $self->{preprocess};
    my ($version, $platform_id, $prodduct_id, $component, $sub_component);
    my $backport_type="";
    #
    # Get bug Details
    #
    my ($base_bug, $version, $platform_id, $product_id,
        $component, $ub_component) =
            $preprocess->get_bug_details_from_bugdb($backport_bug);

    my $gen_or_port = $preprocess->get_gen_port($backport_bug);

    my $param_name = $product_id . "_FAILURE_ALERT_DETAILS";
    my $param_value = "";

    eval
    {
        ($param_value) = ARUDB::exec_sf(
            'aru_parameter.get_parameter_value', $param_name);
    };

    if($@)
    {
        $self->{log_fh}->print("\nNo failure alert defined for BugDB " .
                               "product $product_id\n");
        return;
    }

    #
    # First element will be email id
    # followed by for which backports its enabled
    #
    my @param_details = split(/,/, $param_value);

    my $send_mail  = 0;
    my $enable_blr = 0;
    my $enable_mlr = 0;
    my $enable_ci  = 0;
    my $enable_rfi = 0;

    foreach my $i (@param_details)
    {
        $enable_blr = 1 if ($i eq "BLR:1");
        $enable_mlr = 1 if ($i eq "MLR:1");
        $enable_ci  = 1 if ($i eq "CI:1");
        $enable_rfi = 1 if ($i eq "RFI:1");
    }

    $send_mail = 1, $backport_type = 'BLR'
        if ($gen_or_port eq "B" && $enable_blr == 1);
    $send_mail = 1, $backport_type = 'MLR'
        if ($gen_or_port eq "M" && $enable_mlr == 1);
    $send_mail = 1, $backport_type = 'CI'
        if ($gen_or_port eq "Z" && $enable_ci  == 1);
    $send_mail = 1, $backport_type = 'RFI'
        if ($gen_or_port eq "I" && $enable_rfi == 1);

    if ($send_mail == 0)
    {
        $self->{log_fh}->print("\nEmail notification is not enabled\n");
        return;
    }

    my $email_to = $param_details[0] . '@oracle.com';

    my $blr_url = "<a href='https://bug.oraclecorp.com/pls/bug/" .
                "webbug_print.show?c_rptno=$backport_bug'> $backport_bug </a>";

    my $base_bug_url = "<a href='https://bug.oraclecorp.com/pls/bug/" .
                       "webbug_print.show?c_rptno=$base_bug'> $base_bug </a>";

    my $log_link = "<a href='http://" . APF::Config::url_host_port .
                   "/ARU/BuildStatus/process_form?rid=" .
                   $self->{request_id} . "'> here </a>";

    my $email_content=
       "Backport automation failed to process backport:". $blr_url.
       ", Base Bug: ". $base_bug_url . ".</br>"                 .
       "This requires your attention.</br></br>"                .
       "For details on the next steps required, please check " .
       "the details in the BLR Bug $blr_url. </br>" .
       "<u><b>Details:</b></u></br>"                            .
       "BLR Bug Number: ". $blr_url. "</br>"                    .
       "Base Bug Number: ".  $base_bug_url . "</br>"            .
       "Utility Version   : $version </br>"                 .
       "Component   : $component</br>"                    .
       "Sub Component   : $sub_component\n\n</br></br>"   .
       "<u>Automation failed with following error:</u></br></br>";

    $email_content .= $err_msg;

    $email_content .= "</br></br> Log files can be viewed ". $log_link .
                            " (Request ID: ". $self->{request_id}. ").";

    $email_content .= "</br></br>Please log a bug against 1057/BKPT_AUTO " .
                      "if you feel there is any issue with automation.";

    my $email_subject = "Action: $backport_type:$backport_bug, Product ID:".
                        "$product_id, Component:$component, Reason:$test_name".
                        " handed over by APF";

    my $from     = ISD::Const::isd_do_not_reply;
    my $reply_to = $email_to;


    $self->{log_fh}->print( "\nSending Email alert with below Info:\n");
    $self->{log_fh}->print( "\nEmail Content:\n$email_content:\n"     );
    $self->{log_fh}->print( "\nSubject:$email_subject:\n"             );
    $self->{log_fh}->print( "\nTO:$email_to:\n"                             );
    $self->{log_fh}->print( "\nFrom:$from\n"                          );
    $self->{log_fh}->print( "\nReply-to:$reply_to\n\n"                );

    my $base;
    if(defined($self->{base_ref}))
    {
        $base = $self->{base_ref};
    }
    else
    {
        $base =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                    request_id => $self->{request_id},
                                    pse    => $self->{params}->{bug} ||
                                    $self->{preprocess}->{pse},
                                    aru_obj => $self->{aru_obj},
                                    log_fh => $self->{log_fh});
    }

    $base->_send_mail($self->{log_fh},
                      $email_subject,
                      $email_content,
                      $email_to,
                      $from,
                      $reply_to);

}

sub _postmergeprocess
{
    my ($self, $params) = @_;

    $self->{log_fh} = $self->{aru_log};
    my $bugfix_request_id = 0;

    eval
    {
      $bugfix_request_id = ARUDB::exec_sf('pbuild.get_bugfix_request_id',
                                           $params->{backport_bug});
    };

    #
    # if CI gets diferred, we will not get value from get_bugfix_request_id
    #
    if ($@ || $bugfix_request_id == 0)
    {
        ($bugfix_request_id) = ARUDB::single_row_query('GET_BUGFIX_REQUEST_ID',
                               $params->{backport_bug});
    }

    my $preprocess      = APF::PBuild::PreProcess->new($params);
    $self->{preprocess} = $preprocess;
    $preprocess->preprocessMerge($bugfix_request_id, 1);
    $self->{preprocess} = $preprocess;
    $self->{bugfix_request_id} = $bugfix_request_id;

    my $gen_or_port     = $preprocess->get_gen_port($params->{bug});
    $self->{gen_port}   = $gen_or_port;

    my $work_area  = $preprocess->{work_area};
    my $aru_obj    = $preprocess->{aru_obj};
    my $log_fh     = $self->{aru_log};
    my $request_id = $params->{request_id};

    my $merge =  APF::PBuild::Merge->new($aru_obj, $request_id,
                                         $work_area, $log_fh);


    $merge->{backport_bug}   = $params->{backport_bug};
    $merge->{transaction}    = $params->{txn};
    $merge->{base_bug}       = $params->{base_bug};
    $merge->{merge_action}   = lc($params->{merge_action});
    $merge->{mergereq_id}    = $params->{mergereq_id};
    $merge->{aru_obj}        = $preprocess->{aru_obj};
    $params->{action_desc} = "Commit Transaction";
    $log_fh->print_header($params->{action_desc});

    $merge->postMergeProcess();

    $self->{preprocess} = undef;
}

#
# Switch platform
#
sub _switch_aru_platform {
  my ($self) = @_;
  #
  ## Set platform to Linux x86-64 if the bugdb platform is Generic
  ## and has platform specific files
  #
  my $aru_obj = $self->{aru_obj};

  if (($aru_obj->{platform_id} == ARU::Const::platform_generic) &&
       ($aru_obj->{language_id} == ARU::Const::language_US)) {

    my $cmd_obj = ($self->{remote}) ? $self->{remote_ssh} : $self->{system};
    my $cmd = "uname -om";
    $cmd_obj->do_cmd_ignore_error(
               $cmd,(keep_output => 'YES',
                     timeout => PB::Config::ssh_timeout));
    my (@output) = $cmd_obj->get_last_do_cmd_output();
    foreach my $line (@output) {
      chomp($line);
      if (($line =~ /x86_64/) && ($line =~ /Linux/)) {

        # Set aru_obj platform id to 226
        # ARU::Const::platform_linux64_amd

        my ($new_aru_no) =
               ARUDB::exec_sf("pbuild.update_aru_platform_id",
                              $aru_obj->{aru},
                              ARU::Const::platform_linux64_amd,
                              "Has port-specific files,changing platform id",
                              ARU::Const::apf2_userid);
        if ($new_aru_no) {
          $self->{bugfix_request_id} = $new_aru_no;
          $self->{aru_obj_old} = $aru_obj;
          $aru_obj = new ARU::BugfixRequest($self->{bugfix_request_id});
          $aru_obj->get_details();
          $aru_obj->get_bugfix();
          $aru_obj->{ARU_PSE_BUG} = $self->{aru_obj_old}->{ARU_PSE_BUG};
          $self->{aru_obj} = $aru_obj if ($self->{aru_obj});
          $self->{aru_log}->print(
                 "Switched $self->{aru_obj_old}->{platform_id}:" .
                 "$self->{aru_obj_old}->{aru} " .
                 "to $self->{aru_obj}->{platform_id}:" .
                 "$self->{aru_obj}->{aru}\n");
          $self->{switched_aru_platform} = 1;

          #
          # Bug 15978054 - seed txn attributes for linux aru based on
          # generic aru txn attributes
          #
          my $generic_aru_txn_attribs =
              ARUDB::query('GET_ALL_ARU_TXN_ATTRIBUTES',
                           $self->{aru_obj_old}->{aru});
          my ($txn_id) =
                ARUDB::exec_sf('aru.aru_transaction.get_transaction_id',
                               $aru_obj->{bugfix_id}, $aru_obj->{aru});
          foreach my $row (@$generic_aru_txn_attribs)
          {
              my ($name, $value) = @$row;
              my ($new_aru_attrib) =
                  ARUDB::exec_sf('aru.aru_transaction.get_attribute_value',
                                 $txn_id, $name, ['boolean', 0]);
              if  ($new_aru_attrib ne $value or (! $new_aru_attrib))
              {
                  ARUDB::exec_sp("aru.aru_transaction.add_attribute",
                                 $txn_id, $name, $value);
              }
          }
        }
        last;
      }
    }
  }
}

sub _checkorareviewstatus
{
    my ($self, $params) = @_;

    my $log_fh          = $self->{aru_log};

    $self->{bugfix_request_id} = $params->{bugfix_req_id};
    my $preprocess      = APF::PBuild::PreProcess->new($params);
    $self->{preprocess} = $preprocess;
    my $gen_or_port     = $preprocess->get_gen_port($params->{backport_bug});
    $self->{gen_port}   = $gen_or_port;
    $preprocess->preprocessMerge($self->{bugfix_request_id}, 1);
    $self->{preprocess} = $preprocess;

    my $work_area = $preprocess->{work_area};
    my $bug       = $preprocess->{bug};
    my $aru_obj   = $preprocess->{aru_obj};
    my $base_bug  = $preprocess->{base_bug};

    $self->{workarea} = $work_area;
    $self->{log_fh}   = $log_fh;
    $self->{aru_obj}  = $aru_obj;
    $self->{base_bug} = $base_bug;

    $log_fh->print_header('Check Orareview Status');

    my $merge =  APF::PBuild::Merge->new($aru_obj, $self->{request_id},
                                         $work_area, $log_fh);

    $merge->{backport_bug}     = $params->{backport_bug};
    $merge->{base_bug}         = $params->{base_bug};
    $merge->{transaction}      = $params->{transaction};
    $merge->{aru_obj}          = $aru_obj;
    $merge->{orareview_req}    = $params->{orareview_req_id};
    $merge->{parent_txn_lst}   = $params->{parent_trans};
    $merge->{source_trans}     = $params->{parent_trans};

    $merge->getOrareviewStatus();

    $self->{preprocess} = undef;
}


#
# This is called when there is not DTE or any install tests.
#
sub install_test_updates
{
    my ($self, $log_fh, $aru_no, $version, $pse) = @_;

    #
    # In these cases neither DTE nor EMS templates are available.
    # Therefore give a message that SE team would test this manually.
    # The patch should show to be built successfully.
    #
    # Note:Incase the aru comments is modified, modify the code in
    # AutoPort.pm as well.
    #
    my $msg_no_test = "No DTE or automated test available for this product" .
        " at present. Patch to be tested manually.";

    $log_fh->print("\n\n************* NOTE FOR SE TEAM *************\n");
    $log_fh->print("$msg_no_test \n");
    $log_fh->print("      **********************************\n");

    ARUDB::exec_sp("aru_request.update_aru", $aru_no,
                   ARU::Const::patch_ftped_internal,
                   "", ARU::Const::apf2_userid, $msg_no_test);

    $self->_update_bug($pse, {status  => 52,
                              programmer    => 'PATCHQ',
                              test_name     => 'APF-TEST-NOTDEFINED',
                              version_fixed => $version,
                              body => $msg_no_test});

    ARUDB::exec_sp("pbuild.update_step_status",
                   $self->{request_id},
                   ISD::Const::isd_request_stat_fail)
            if ($self->{request_id});

    #
    # Send notification if this is BP
    #
    ($self->{patch_type}) = ARUDB::single_row_query('GET_PATCH_TYPE',
                                                    $aru_no);

    if ($self->{patch_type} == ARU::Const::ptype_cumulative_build)
    {
        my $aru_obj     = $self->{aru_obj};
        my $status_link = "http://" . APF::Config::url_host_port .
                "/ARU/BuildStatus/process_form?rid=".$self->{request_id};
        my $request_link = "<a href=\"$status_link\">$self->{request_id}</a>";
        my $options = {
            'aru_obj'       => $aru_obj,
            'log_fh'        => $log_fh,
            'product_id'    => $aru_obj->{product_id},
            'release_id'    => $aru_obj->{release_id},
            'version'       => $aru_obj->{release} ||
                               $aru_obj->{release_long_name},
            'product_name'  => $aru_obj->{product_name},
            'subject'       => "APF Patch Creation completed but " .
                               "Install Tests not invoked for",
            'comments'      => "is packaged. Install Tests not configured",
            'qa_output'     => 'Install Tests is not configured in APF',
            'output_column' => 'Install Test output',
            'platform'      => $aru_obj->{platform},
            'bug'           => $aru_obj->{bug},
            'label'         => $self->{bpr_label},
            'request_log'   => $request_link,
          };

        APF::PBuild::Util::send_bp_email_alerts($options);
    }
}

#
# To create the soft link for the minimum opatch version base directory
#
sub create_link_for_opatch_dir
{
    my ($self, $min_opatch_ver, $wkr_host,
        $min_opatch_path, $host_type, $release_id, $release_name) = @_;

    my ($status);
    my $cpct_release_id;
    my $is_cpct_release = ARUDB::exec_sf_boolean('aru.pbuild.is_cpct_release',
                                                 '',
                                                 $release_name,
                                                 \$cpct_release_id);

    my $opatch_release = $min_opatch_ver;
    $opatch_release =~ s/^(\d+\.\d+)\..*/$1/;
    $min_opatch_path =
        $min_opatch_path."/OPATCH_".$opatch_release.".0_GENERIC.rdd";
    $min_opatch_path =
        $min_opatch_path."/RELEASE_".$min_opatch_ver."/opatch/OPatch";

    my $email_subject = "APFCLI failed to create the OPATCH link for the ".
        "release $release_name";
    my ($mail_recepients, $email_content);

    if (ConfigLoader::runtime("production")) {
        $mail_recepients = APF::Config::min_opatch_op_contact_list;
    } else
    {
        $mail_recepients = APF::Config::min_opatch_dev_contact_list;
    }

    my $timeout  = APF::Config::ssh_timeout;
    #
    # Checking whether the base directory exists
    #
    $status = 0;
    my $destPath = APF::Config::ade_opatch_path;
    $destPath = $destPath."/".$min_opatch_ver;
    my $log_fh = $self->{aru_log};

    my $ssh_status = 1;
    my $user = PB::Config::remote_user;

    my $ade_site = _get_ade_site($wkr_host);

    my $remote_cmd = 'setenv ADE_SITE '.$ade_site.' \; tcsh';

    my $ssh = DoRemoteCmd->new({user       => $user,
                                host        => $wkr_host,
                                setup_env   => 0,
                                remote_command => $remote_cmd,
                                filehandle => $self->{log_fh}});
    unless ($ssh)
    {
        $ssh_status = 0;
    }

    $ssh->set_filehandle($log_fh);
    my $default_cmd = "hostname";
    $self->{base_ref}->exec_retry_command
        (do_cmd_obj => $ssh,
         method     => 'do_cmd_ignore_error',
         args       => [$default_cmd,(keep_output => 'YES',
                              timeout => $timeout)]);
    my (@default_output) = $ssh->get_last_do_cmd_output();
    $ssh_status = 0 if ($ssh_status == 1);
    foreach my $line (@default_output)
    {
        chomp ($line);
        if ($wkr_host =~ m/$line/)
        {
            $ssh_status = 1;
        }
    }

    my @grep_result;
    my @output;
    if ($ssh_status == 1)
    {
        my $ls_cmd = "ls $min_opatch_path/opatch";
        $self->{base_ref}->exec_retry_command
            (do_cmd_obj => $ssh,
             method     => 'do_cmd_ignore_error',
             args       => [$ls_cmd,(keep_output => 'YES',
                                          timeout => $timeout)]);
        @output = $ssh->get_last_do_cmd_output();
        $status = $self->_hnd_errors($ssh);
        @grep_result = grep /No such file or directory/i, @output;
    }
    else
    {
        $log_fh->print("DEBUG: SSH connection to the host : $wkr_host".
                       " is having some issues. Minimum opatch ".
                       "locations cannot be created due to ssh issues.".
                       " Please check ...\n");
    }


    if ($#grep_result == -1 && $status == 0 && $ssh_status == 1)
    {
        #
        # Checking whether the respective opatch version directory
        # exists on the host
        #
        my $lscmd_destpath = "ls $destPath/opatch";
        $self->{base_ref}->exec_retry_command
            (do_cmd_obj => $ssh,
             method     => 'do_cmd_ignore_error',
             args       => [$lscmd_destpath,(keep_output => 'YES',
                                          timeout => $timeout)]);
        my @ls_output = $ssh->get_last_do_cmd_output();
        $status = $self->_hnd_errors($ssh);
        my @ls_grep_result = grep /No such file or directory/i, @ls_output;
        my @ln_output;
        if ($#ls_grep_result != -1 &&  $status == 0)
        {
            #
            # Creating the soft link on the worker host
            #
            my $ln_cmd = "ln -s $min_opatch_path $destPath";
            $self->{base_ref}->exec_retry_command
            (do_cmd_obj => $ssh,
             method     => 'do_cmd_ignore_error',
             args       => [$ln_cmd,(keep_output => 'YES',
                                          timeout => $timeout)]);
            @ln_output = $ssh->get_last_do_cmd_output();
            $status = $self->_hnd_errors($ssh);
        }

        if ($status == 0)
        {
            #
            # Verifying the link is created or not on the worker host
            #
            my $dest_ls_cmd = "ls $destPath/opatch";
            $self->{base_ref}->exec_retry_command
            (do_cmd_obj => $ssh,
             method     => 'do_cmd_ignore_error',
             args       => [$dest_ls_cmd,(keep_output => 'YES',
                                          timeout => $timeout)]);
            @output = $ssh->get_last_do_cmd_output();
            $status = $self->_hnd_errors($ssh);
            my @dest_ls_grep_result =
                grep /No such file or directory/i, @output;
            if ($#dest_ls_grep_result != -1)
            {
                $status = 1;
            }
        }
    } else
    {
        $email_content  = "The Minimum opatch central directory '".
            $min_opatch_path."' is missing on the $host_type host $wkr_host.\n".
             "Please use this command to create the link manually :\n".
             "ln -s $min_opatch_path $destPath";

        $self->{base_ref}->_send_mail($self->{aru_log}, $email_subject,
                                      $email_content, $mail_recepients);
    }

    if ($status == 1)
    {
        $email_content = "Unable to create the link using the central ".
            "directory '".$min_opatch_path."' on the $host_type host".
                "$wkr_host.\n ".
                    "Please use this command to create the link manually :\n".
                        "ln -s $min_opatch_path $destPath";
        $self->{base_ref}->_send_mail($self->{aru_log}, $email_subject,
                                      $email_content, $mail_recepients);
    }
}

#
#This will throw an error when any process failed because of
# maximum idle time or if mkdir fails.
#
sub _hnd_errors
{
    my ($self,$ssh) = @_;
    my $status = 0;
    my @output = $ssh->get_last_do_cmd_output();
    foreach my $out (@output)
    {
       chomp($out);

       if ($out =~ m/timed out after/i)
       {
           $status = 1;
           last;
       }

       if ($out =~ m/Password/i)
       {
           $status = 1;
           last;
       }

     }
    return $status;
}
#
#
#
sub _seed_child_labels
{
    my ($self, $params) = @_;

    my $cpct =  APF::PBuild::cpct_common->new($self->{request_id},
                                              $self->{aru_log});

    $cpct->seed_labels($params);
}

sub _get_emcc_tag {

  my ($self, $it_obj) = @_;

  my $aru = $it_obj->{aru_obj}->{aru};
  my $emcc_tag = "";

  $self->{emcc_installtest} =
        APF::PBuild::Util::is_emcc_installtest($it_obj->{aru_obj});

  return $emcc_tag if (!$self->{emcc_installtest});

  $emcc_tag =
       ($it_obj->{has_postinstall_sql}) ?
        "APF-EMCC-SQL-INSTALLTEST-SUCCESS" :
        "APF-EMCC-INSTALLTEST-SUCCESS";

  my $testflow_name = "Install Test - EMCC";
  my @testrun_details = ARUDB::query('GET_EMCC_TESTRUN_DETAILS',
                                     $testflow_name, $aru);

  my $no_of_tests_run = 0;

  my ($tr_testrun_id, $tr_label_id, $tr_platform_id, $tr_release_id,
      $tr_testflow_id, $last_testsuite_name);

  $last_testsuite_name = "TESTS-NOTDEFINED";

  foreach my $test_rec (@testrun_details)
  {
    $no_of_tests_run++;
    my ($testresult_id, $tr_status_id, $testsuite_name);
    ($tr_testrun_id, $tr_label_id, $tr_platform_id, $tr_release_id,
     $testresult_id, $tr_status_id, $tr_testflow_id,
     $testsuite_name) = @$test_rec;

    $last_testsuite_name = $testsuite_name;
  }

  my ($total_tests);
  my $found = 0;

  my $fname = $it_obj->{work_area} . "/testcount.lst";
  if (-e $fname) {
    open (FH, "< $fname");
    my @fcontents = <FH>;
    close FH;
    foreach my $rec (@fcontents) {
      chomp($rec);
      my ($token1, $token2) = split(/=/,$rec);
      if ($token1 =~ /Count/) {
        $total_tests = $token2;
        $found = 1;
        last;
      }
    }
  }

  if (!$found) {
    ($total_tests) = ARUDB::single_row_query('GET_EMCC_TESTS_COUNT',
                                             $tr_label_id);
  }

  my $task_name = uc($last_testsuite_name);
  $task_name =~ s/ /_/g;

  if (($no_of_tests_run == 0) ||
      ($total_tests != $no_of_tests_run)) {
    $task_name .= "-FAIL";
    $emcc_tag =~ s/SUCCESS/$task_name/g;
  }

  return $emcc_tag;
}



sub send_alert_on_P1_BLR_failure
{
    my ($self, $assignee, $bug, $base_bug, $bug_text, $count) = @_;

    my $log_fh     = $self->{log_fh};
    my $preprocess = $self->{preprocess};

    my ($utility_ver, $bugdb_platform_id,$bugdb_prod_id,
        $bugdb_component, $bugdb_sub_component);

    #
    # Get bug Details
    #
    ($base_bug, $utility_ver, $bugdb_platform_id, $bugdb_prod_id,
     $bugdb_component, $bugdb_sub_component) =
         $preprocess->get_bug_details_from_bugdb($bug);

    my $parent_product_id;

    my ($product_id, $product_abbr);

    #
    # Check if below call died with unknown aru product
    # See Bug : 19462189
    #
    eval {
        ($product_id, $product_abbr) =
            APF::PBuild::Util::get_aru_product_id($bugdb_prod_id, $utility_ver);
    };

    unless ($@)
    {

        #
        # if its child product id then get family product id
        #
        if ($product_id != ARU::Const::product_oracle_database)
        {
            my $product_type = ARU::Const::product_type_family;
            ($parent_product_id) = ARUDB::single_row_query(
                                                   "GET_PARENT_PROD_ID",
                                                   $product_id,
                                                   $product_type);
        }
        else
        {
            $parent_product_id = $product_id
        }

        $log_fh->print( "\nParent Product Id:$parent_product_id\n");

        #
        # Do not send e-mail if its not Database product
        #
        return if ($parent_product_id != ARU::Const::product_oracle_database);

    }else{

        $log_fh->print( "\nUnknown Product:$bugdb_prod_id\n$@\n\n");
    }

    my $area_mgr = PB::Config::all_SE_DB_Managers;

    #
    # Get area queue
    #
    my ($qown, $qownmail, $dev_owner, $active_flag, $platform);

    my $result_ref;

    eval
    {
        $result_ref = ARUDB::query('GET_AREA_MANAGER_DETAILS',
                $bugdb_prod_id, $bugdb_component, $bugdb_sub_component);
    };

    #
    # Check for result is not null
    #
    if (defined($result_ref) && defined($result_ref->[0])
       && (defined($result_ref->[0]->[1]) && $result_ref->[0]->[1] ne ''))
    {
    ($qown, $qownmail, $dev_owner, $area_mgr, $active_flag, $platform) =
                                                    @{$result_ref->[0]};
    }


    $area_mgr = $qownmail
        if ((defined($qownmail)) && $qownmail ne '');

    $area_mgr .= '@oracle.com' if $area_mgr ne '';

    #
    # if count is not 1 that means, we did not got base bug
    # owner, so we should be using default value
    #

    my ($assignee_email, $manager_email, $apf_mail);

    $apf_mail = PB::Config::p1_cc_recepients . '@oracle.com';

    if ($count == 1)
    {
        #
        # get developer and manager's email ids
        ($assignee_email, $manager_email) = ARUDB::single_row_query(
                                          'GET_MANAGER_EMAIL', uc($assignee));

        #
        # No LUCK !! Assign it to default 'amangal_managers_ww@oracle.com'
        #
        if(( $assignee_email eq '' ) || ( $assignee_email =~  /^\s*$/ ) )
        {
            #
            # If we don't get email's details then there is some issue
            #
            $assignee_email = PB::Config::all_SE_DB_Managers;
        }

        $manager_email .= '@oracle.com' if $manager_email ne '';
    }
    else
    {
        $assignee_email = PB::Config::all_SE_DB_Managers;
    }

    $assignee_email .= '@oracle.com' if $assignee_email ne '';

    my $to = $assignee_email;
    my $cc_mail_recepients = '';
    $cc_mail_recepients .= "$manager_email," if $manager_email ne '';
    $cc_mail_recepients .= "$area_mgr, $apf_mail";

    my $backport_triage_assignee = "";
    my $backport_triage_email = "";

    # PB::Config::backport_triage_assignee;
    # PB::Config::backport_triage_email;

    eval {
      ($backport_triage_assignee) = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                    'BACKPORT_TRIAGE_ASSIGNEE');
    };

    $backport_triage_assignee ||= "BKPTRGQ";

    if ($assignee eq "$backport_triage_assignee") {
      eval {
        ($backport_triage_email) = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                    'BACKPORT_TRIAGE_EMAIL');
      };
      $backport_triage_email ||= "apf_backport_operations_us_grp\@oracle.com";
      $to = $backport_triage_email;
      $cc_mail_recepients = "";
    }

    my $bug_url = '';

    $bug_url = 'https://bug.oraclecorp.com/pls/bug/';

    my $blr_url = "<a href='$bug_url" .
                     "webbug_print.show?c_rptno=$bug'> $bug </a>";

    my $base_bug_url = "<a href='$bug_url" .
                "webbug_print.show?c_rptno=$base_bug'> $base_bug </a>";

    my $log_link = "<a href='http://" . APF::Config::url_host_port .
       "/ARU/BuildStatus/process_form?rid=". $self->{request_id}   .
                                                     "'> here </a>";

    my $email_content=
       "Backport Automation failed to process P1 BLR Bug:". $blr_url.
       ", Base Bug: ". $base_bug_url . ".</br>"                 .
       "This requires your attention.</br></br>"                .
       "For details on the next steps required, please check " .
       "the details in the BLR Bug $blr_url. </br>" .
       "<u><b>Details:</b></u></br>"                            .
       "Assignee: $assignee</br>"                               .
       "BLR Bug Number: ". $blr_url. "</br>"                    .
       "Base Bug Number: ".  $base_bug_url . "</br>"            .
       "Utility Version   : $utility_ver </br>"                 .
       "Component   : $bugdb_component</br>"                    .
       "Sub Component   : $bugdb_sub_component\n\n</br></br>"   .
       "<u>Automation failed with following error:</u></br></br>";

    $email_content .= $bug_text;

    $email_content .= "</br></br> Log files can be viewed ". $log_link .
                            " (Request ID: ". $self->{request_id}. ").";

    $email_content .= "</br></br>Please log a bug against 1057/BKPT_AUTO " .
                      "if you feel there is any issue with automation.";

    my $email_subject = "Action Required: P1 BLR:$bug, ".
                   "Base Bug:$base_bug assigned to you.";

    my $from         = ISD::Const::isd_do_not_reply;
    my $reply_to     = $area_mgr;

    $log_fh->print( "\nSending Email alert with below Info:\n");
    $log_fh->print( "\nEmail Content:\n$email_content:\n"     );
    $log_fh->print( "\nSubject:$email_subject:\n"             );
    $log_fh->print( "\nTO:$to:\n"                             );
    $log_fh->print( "\nCC:$cc_mail_recepients\n"              );
    $log_fh->print( "\nFrom:$from\n"                          );
    $log_fh->print( "\nReply-to:$reply_to\n\n"                );


    my $base;
    if(defined($self->{base_ref}))
    {
        $base = $self->{base_ref};
    }
    else
    {
    $base =  APF::PBuild::Base->new(work_area  => $self->{aru_dir},
                                    request_id => $self->{request_id},
                                    pse    => $self->{params}->{bug} ||
                                    $self->{preprocess}->{pse},
                                    aru_obj => $self->{aru_obj},
                                    log_fh => $self->{log_fh});
    }

    my $mail_recepients;

    $mail_recepients = $to
        if ($to =~ /.+\@oracle.com/);

    $mail_recepients .= "," . $cc_mail_recepients
        if ($cc_mail_recepients =~ /.+\@oracle.com/);

    $base->_send_mail($log_fh,
                      $email_subject,
                      $email_content,
                      $mail_recepients,
                      $from,
                      $reply_to);

}


#
# Validate request status
#
sub validate_request
{
    my ($self, $params) = @_;

    my $status;

    my $req_obj =  APF::PBuild::ValidateRequest->new($params);

    #
    # Validate request and return status
    #
    $status = $req_obj->validate_request();

    $self->{err_msg} = $req_obj->{err_msg}
                            unless $status;

    return $status;
}

#
# To update the bug status to 55 when the check-in status in ARU
# is set to "On Hold"
#
sub update_on_hold_bug_status
{
    my ($self, $bug, $bug_msg) = @_;

    my $bug_txt = "Checkin status in ARU is set to 'On Hold', so ".
                  "updating the bug status to 55";
    $bug_txt = $bug_msg . "\n" . $bug_txt if ($bug_msg ne "");

    my ($programmer, $version_fixed, $test_name, $bug_current_status)
         = ARUDB::single_row_query("GET_BUG_UPDATE_DETAILS",
                                   $bug);
    #
    # Update the bugdb.
    #
    $self->_update_bug($bug, {status        => 55,
                              body          => $bug_txt,
                              programmer    => $programmer,
                              test_name     => $test_name,
                              version_fixed => $version_fixed,
                              on_hold_patch => 1});
    return;
}


#
# Check Given user is valid or left company
#
sub is_valid_user
{
    my ($self, $bug_user) = @_;

    my ($status) =
        ARUDB::single_row_query("GET_USER_STATUS",
                                $bug_user);
    return $status;

}


#
# Check aru_parameters table for
# description 'BUG ASSIGNMENT'
# if found return status true.
#
sub is_patchQ_product
{
    my ($self,$bugdb_prod_id, $g_or_p) = @_;

    my $status;
    my $patchq_prods;

    if($g_or_p eq 'O')
    {
        ($patchq_prods) = ARUDB::single_row_query("GET_PATCH_LEVEL",
                                            'PSE_ASSIGNMENT');

        my @split_prods = split(/\s*,\s*/,$patchq_prods);
        chomp(@split_prods);

        if (($bugdb_prod_id ne '' ) &&
            (grep(/^$bugdb_prod_id$/,@split_prods)))
        {
            $status = 1;
        }
        else
        {
            $status = 0;
        }

        $self->{log_fh}->print('Status: '.$status."\n");

    }
    else
    {

        ($status) = ARUDB::single_row_query("GET_MLR_ASG_PARAM",
                                            '%,'.$bugdb_prod_id.',%');
    }

    return $status;
}

#
# Send notification for a valid(B/I/Z) requests
#
sub send_notification_for_backports
{
    my ($self,$bug,$gen_or_port) = @_;

    return if (!defined($bug));

    #
    # notification only needs to send for BLR/CI
    #
    if (($gen_or_port eq 'B') || ($gen_or_port eq 'Z'))
    {
        my $flag = 'Y';

        if ($gen_or_port eq 'B')
        {
            my $bkp_status;
            ARUDB::exec_sp('bugdb.get_bug_status', $bug, \$bkp_status);

            $self->{log_fh}->print("\nSending Assignemnt notification..\n")
                if($bkp_status !~ /35|74|75|80|90|93/);

            ARUDB::exec_sp('aru_cumulative_request.send_cpm_alert',
                           'notify_ci_assignment',$bug,['boolean',$flag])
                if($bkp_status !~ /35|74|75|80|90|93/);
        }
        else
        {
            $self->{log_fh}->print("\nSending Assignemnt notification...\n");

            ARUDB::exec_sp('aru_cumulative_request.send_cpm_alert',
                           'notify_ci_assignment',$bug,['boolean',$flag]);
        }
    }
}


#
# function to fetch the username who submitted the install test
#
sub _get_install_test_submit_user
{
    my ($self, $request_id) = @_;
    my $assignee = 'PATCHQ';
    my ($user_name)=ARUDB::single_row_query("GET_INSTALLTEST_SUBMIT_USER",
                                              $request_id, ISD::Const::st_apf_install_type);
    if(($user_name ne 'APFMGR') &&
       ($user_name ne 'APFWKR') &&
       ($user_name ne 'ARUDEMO') &&
       ($user_name ne 'APFNLS'))
    {
        my $user_status = $self->is_valid_user($user_name);
        if($user_status)
        {
            $assignee = $user_name;
        }

    }
    return $assignee;

}

sub _get_test_name
{
    my ($self, $aru_obj, $err_msg) = @_;

    my $testname = "APF-FAIL";
    my $default_testname = "APF-FAIL";

    $aru_obj ||= $self->{aru_obj};

    #
    # Parse log files to get a proper test name
    # For Build and Install Test request types
    #
    my $request_logdir = "$self->{base_work}/$self->{request_id}/log";
    my $hash_file = "$request_logdir/pbdaemon_hash.lst";

    my $req_type_code = $self->{request}->{type_code};
    if (exists $self->{log_fh}->{basename})
    {
        my ($l_prefix, $l_req_id, $l_timestamp) =
        split(/_/,$self->{log_fh}->{basename});
        $hash_file = "$request_logdir/pbdaemon_hash_". $l_timestamp . ".lst";
    }

    $self->{pbdaemon_hash_file} = $hash_file;

    my $err_code = "";
    my $err_ranking;
    my $err_codes_array = "";

    my $request_logfile = $self->{failed_task_obj}->{request_logfile} || "";
    my $testname_prefixes = ERR::Config::test_name_prefix;
    $err_code =
        $self->{failed_task_obj}->{failure}->{details}->{err_code} || "";

    if ($err_code eq "")
    {
        my $task = $self->{params}->{action_desc} || "";
        $self->{log_fh}->print("DEBUG: Request Logdir: $request_logdir\n" .
                               "Request Logfile: $request_logfile\n" .
                               "ErrMsg: $err_msg\n" .
                               "Task: $task\n");
        ($err_code, $err_ranking, $err_codes_array) =
            APF::PBuild::APFLogParsers::get_err_code_from_logfile(
                    $request_logfile, $request_logdir, $err_msg, $task, 1);

        $self->{log_fh}->print("DEBUG: ErrCode1: $err_code\n");

        if ($err_code eq "")
        {
            ($err_code, $err_ranking, $err_codes_array) =
                  APF::PBuild::APFLogParsers::get_err_code_from_logfile(
                  "", $request_logdir, "", $task, 1);
            $self->{log_fh}->print("DEBUG: ErrCode2: $err_code\n");
        }

        if ($err_code eq "")
        {
            ($err_code, $err_ranking, $err_codes_array) =
                  APF::PBuild::APFLogParsers::get_err_code_from_logfile(
                  "", $request_logdir, "", "", 1);
            $self->{log_fh}->print("DEBUG: ErrCode3: $err_code\n");
        }

    }

    $self->{failed_task_obj}->{failure}->{details}->{err_code} = $err_code;
    $self->{failed_task_obj}->{failure}->{details}->{err_ranking} =
                                                           $err_ranking;
    $self->{failed_task_obj}->{failure}->{details}->{other_errors} =
                                                           $err_codes_array;

    my $err_code_props =
         APF::PBuild::APFLogParsers::get_error_code_properties($err_code);
    $self->{failed_task_obj}->{failure}->{details}->{error_code_props} =
                                                           $err_code_props;

    my $err_code_without_prefix = $err_code;
    $self->{throttle_error_code} = $err_code_without_prefix;

    $err_code = $testname_prefixes->{$req_type_code} .
                $err_code if ($err_code ne "");
    $testname = ($err_code eq "") ? "APF-FAIL" : $err_code;

    $self->{failed_task_obj}->{failure}->{details}->{test_name} ||= $testname;
    APF::PBuild::InstallTestUtil::dump_output_hash($self, $hash_file);
    if (($aru_obj->{release_id} !~
          /^${\ARU::Const::applications_fusion_rel_exp}\d+$/) &&
        (($req_type_code == ISD::Const::st_apf_build_type) ||
         ($req_type_code == ISD::Const::st_apf_install_type) ||
         ($req_type_code == ISD::Const::st_apf_automate_template) ||
         ($req_type_code == ISD::Const::st_apf_request_task) || 
         ($req_type_code == ISD::Const::st_apf_req_merge_task)))
    {
        #
        # Returning parsed testname only for build, installtest and requests and
        # non fusionapps releases
        #
        $self->{log_fh}->print("DEBUG:_get_test_name:TESTNAME: $testname\n");
    }
    else
    {
        $testname = $default_testname;
    }

    return $testname;
}

#
# get the ade_site value
#
sub _get_ade_site
{
    my ($self, $worker_host) = @_;

    my $ade_site = "";
    if ((defined($worker_host)) && $worker_host ne '')
    {
        my $wkr_dc =
            APF::PBuild::Util::determine_subnet($worker_host);

        my $ade4_sites = PB::Config::ade4_sites;
        $ade_site = $ade4_sites->{$wkr_dc} if ($wkr_dc ne "");

    }
    else
    {
        my $current_host  = Sys::Hostname::hostname();
        my $wkr_dc = APF::PBuild::Util::determine_subnet($current_host);

        my $ade4_sites = PB::Config::ade4_sites;
        $ade_site = $ade4_sites->{$wkr_dc} if ($wkr_dc ne "");

    }

    return $ade_site;
}

#
# Corrective Actions
#
sub corrective_action
{
    my ($self) = @_;

    my $req_param   = $self->{params}->{st_apf_build};

    $req_param .= "!work_area:$self->{aru_dir}";

    my %params;
    foreach my $i (split('!',$req_param))
    {
        my ($key, $value) = split(':',$i);
        $params{$key} = $value;
        $params{lc($key)} = $value;
        $self->{aru_log}->print("Request Parameters : $key - $value \n");
    }

    #
    # Store the ISD request id number
    #
    $params{request_id} = $self->{request_id};
    $params{log_fh}     = $self->{aru_log};

    $self->{params}     = \%params;
    $self->{params}->{grid_id}     = $self->{request}->{grid_id};

    if ($self->{request_id}) {
      $0 .= " - request_id=$self->{request_id},action=$params{action}" .
            ",bug=$params{bug},aru=$params{aru_no}";
    }

    my $action = $params{action} || $params{test_name} ||"";

    die ("Action is not specified for this request") unless($action);

    my $success;
    my $log_fh = $self->{log_fh} = $self->{params}->{log_fh} = $self->{aru_log};

    my $aru_no     = $params{aru_no};
    my $request_id = $params{request_id};
    my $log_fh     = $self->{aru_log};

    $params{log_fh} = $log_fh;

    my $ca_it = new APF::PBuild::APFCorrectiveActions(%params);

    my $header = $params{comments} || $params{task} ||
                 "Process $ca_it->{test_name}";

    #$log_fh->print_header($header . "\n");

    $ca_it->process_request(\%params);

}


sub _proactive_validations
{
    my ($self, $params) = @_;

    my $log_fh = $self->{aru_log};
    my $bug    = $params->{bug};
    my $unique_id_name = $params->{UNIQUE_ID_NAME};
    my $unique_id_value  = $params->{UNIQUE_ID_VALUE};
    my $stage    = $params->{STAGE};
    my $txn = $params->{TXN} || "";

    #
    # Update the workflow to INPROGRESS immediately so it does
    # not get reprocessed.
    #
    ARUDB::exec_sf('aru.checklist_testrun.insert_testrun',
                   $bug, ' ', '', 'SUBMITTED',
                   '', $stage, 'INPROGRESS', 'apfmgr',
                   $unique_id_name, $unique_id_value);

    $log_fh->print("Updated workflow value to INPROGRESS\n");


    my $syscmd = new DoSystemCmd({'no_die_on_error' => 1,
                                  'no_error_output' => 1});

    $syscmd->set_filehandle($self->{log_fh});
    my $cmd = $ENV{ISD_HOME}."/pm/APF/PBuild/utils/proactivevalidations.pl ".
        "--bug $bug --unique_id_name='$unique_id_name'"
            ." --unique_id_value='$unique_id_value' ".
                " --stage=$stage ";
    $cmd .= " --txn=$txn" if (defined($txn) && $txn ne '');

    $syscmd->do_cmd("perl  $cmd");

}

sub _submit_pv_requests
{
    my ($self, $params) = @_;

    my $log_fh = $self->{aru_log};
    my $delay    = $params->{delay};
    my $isd_request_id  = $self->{request_id} || $params->{request_id};


    my ($isd_req_log) = ARUDB::single_row_query("GET_ISD_REQ_LOG",
                                                $isd_request_id);

    $log_fh->print('=' x 100, "\n");
    $log_fh->print("New Cron ISD_REQUEST Process Spawned\n");
    #
    # register the cron start and end time in CRON stage
    #
    my $host          = PB::Config::short_host;
    eval
    {
        $log_fh->print("Inserting Cron details $$\n");
        ARUDB::exec_sf('aru.checklist_testrun.insert_testrun',
                       $$, 'CRON', $host, 'STARTED',
                       '', 'CRON', 'STARTED', 'apfmgr', 'RID', $isd_request_id);
    };


    my $priority = PV::Config::priority_order;

    my @priority_order = split (',', $priority);

    my $count = 1;

    foreach my $order (@priority_order)
    {
        $log_fh->print("\n==>Next Priority Order is $order\n");
        my $priority;
        ($order,$priority) = ($order =~ /(.*)-(.*)/);
        $log_fh->print("Priority for $order is $priority\n");
        my @results = ARUDB::query("GET_PROACTIVE_TESTFLOWS");
        $log_fh->print("Total CPM Series found: " . scalar @results . "\n");

        foreach my $row (@results)
        {
            my ($cpm_series_name) = @$row;
            $cpm_series_name =~ s/Patch Validations for //gi;
            $log_fh->print("CPM Series: $cpm_series_name\n");
            #
            # Check for new requests that have been included in
            # between the sleep  Order by new requests, followed by old
            # requests in INCOMPLETE status Inturn, process the
            # requests based on the priority defined Filter the
            # requests if there is any open bug still and don't
            # resubmit Don't reprocess requests which are already in
            # WAITQ and INPROGRESS
            #

            if ($order == 34588)
            {
                my $stage = "CI_MERGED";
                $log_fh->print("\n\nStage value is $stage\n");

                my $records = ARUDB::query("GET_CI_MERGED_BUGS",
                                           $cpm_series_name);
                $log_fh->print("Total CI_MERGED records: " .
                               scalar @$records . "\n");

                foreach my $row (@$records)
                {
                    my ($bug, $ci_txn) = @$row;
                    $self->submit_to_pv_q($bug,$ci_txn,$stage,
                                          'cpm_series_name',
                                          $cpm_series_name,80020,
                                          1779908,$priority);
                }
            }
            else
            {
                my $stage = "BUG_REVIEW";
                $log_fh->print("\n\nStage value is $stage\n");

                my $records = ARUDB::query("GET_BUG_REVIEW_BUGS",
                                           $cpm_series_name, $order);
                $log_fh->print("Total BUG_REVIEW records: " .
                               scalar @$records . "\n");

                foreach my $row (@$records)
                {
                    my ($bug) = @$row;
                    $self->submit_to_pv_q($bug,'',$stage,'cpm_series_name',
                                    $cpm_series_name,80020,1779908,$priority);

                }
            }
        }
    }


    $log_fh->print("***Completed run_proactive_validations***\n");
    $log_fh->print("Current Time:\t" .`date` . "\n");

    eval
    {
        $log_fh->print("Closing cron in testrun $$\n");
        ARUDB::exec_sf('aru.checklist_testrun.insert_testrun',
                       $$, 'CRON', $host, 'COMPLETED',
                       '', 'CRON', 'COMPLETED', 'apfmgr', 'PID', $isd_request_id);
    };

    #
    #      Suspend the request
    #

    $self->{preprocess}->suspend_request({delay => $delay},
                                         $isd_request_id, $isd_req_log);
    $log_fh->print(`date`." - Suspended the $isd_request_id for $delay day\n");

}



sub submit_to_pv_q
{
    my ($self, $bug, $txn, $stage, $uniq_id, $uniq_id_val,
        $request_type, $user_id, $priority ) = @_;
    my $log_fh = $self->{aru_log};

    #
    # Check for the workflow status
    # Don't request the check if the workflow is complete or inprogress
    #
    my ($workflow, $tasks_status) = ARUDB::single_row_query
        ("GET_WORKFLOW_STATUS",
         $bug,
         $stage,
         $uniq_id,
         $uniq_id_val);

    $log_fh->print("WorkFlow status of $bug $txn and ".
                   "$stage is $workflow ($tasks_status)\n");

    if ($workflow =~ /INCOMPLETE/ && $tasks_status =~ /\d+/)
    {
        my $resubmit = 0;
        my $skip = 0;

        foreach my $tasks (split('#',$tasks_status))
        {
            if ($tasks =~ /\d+/)
            {
                my ($t_bug) = ($tasks =~/\|(.*)/);
                my ($status, $version_fixed, $test_name, $updated_by) =  ARUDB::single_row_query
                    ("GET_SUSPENDED_BUG_DETAILS", $t_bug);

                if (($status ==35 || $status ==90 || $status == 93 ) &&
                    $updated_by !~/ARU/i)
                {
                    $log_fh->print("Re-request the PV $bug as $t_bug ".
                                   "is still in Closed by user; Bug Status - $status \n");
                    $resubmit = 1;
                    last;
                }

                if ($status <=30 || $status ==40)
                {
                    $log_fh->print("Skipping processing $bug as $t_bug ".
                                   "is still in OPEN status - $status \n");
                    $skip = 1;
                }
            }

        }

        #
        # skip running the PV in case there is no resubmit use case and there
        # is an open bug only
        #
        if ($skip && !$resubmit)
        {
            return;
        }
        else
        {
            my $request_id =  ARUDB::exec_sf
                ('aru.pbuild.submit_pv_request',
                 $bug, $txn, $stage,
                 $uniq_id, $uniq_id_val,80020,
                 1779908,$priority);
            $log_fh->print("==> Request ID for $bug, $uniq_id_val ".
                           "and $stage is :   $request_id\n");

        }
    }

    if (!($workflow ) ||
        ($workflow !~ /^COMPLETE|INPROGRESS|WAITING FOR FARM/i))
    {
        my ($re_request) =
            ARUDB::single_row_query("GET_ISDREQUEST_STATUS",
                                    $bug,
                                    "%"."UNIQUE_ID_VALUE:$uniq_id_val"."%");
        $log_fh->print("Prev ISD Request status code is $re_request\n");

        if (($re_request =~ /^30005|30004/) || (!$re_request ))
        {
            my $request_id =  ARUDB::exec_sf
                ('aru.pbuild.submit_pv_request',
                 $bug, $txn, $stage,
                 $uniq_id, $uniq_id_val,80020,
                 1779908,$priority);
            $log_fh->print("==> Request ID for $bug, $uniq_id_val ".
                                   "and $stage is :   $request_id\n");
        }
    }
    else
    {
        $log_fh->print("Bug $bug workflow is already $workflow.\n");
    }

}


sub _checkfarmstatus
{
    my ($self, $params) = @_;

    my $log_fh            = $self->{aru_log};
    my $request_id        = $params->{request_id};
    $self->{request_id} = $request_id
        if (! defined $self->{request_id} || $self->{request_id} eq "");


    my $bugfix_request_id = $params->{bugfix_request_id};

    my $req_params;
    my %farm_params;

    my $preprocess      = APF::PBuild::PreProcess->new($params);
    $self->{preprocess} = $preprocess;
    my $gen_or_port     = $preprocess->get_gen_port($params->{bug});
    $self->{gen_port}   = $gen_or_port;

    eval {
         $self->initialize_git_src_ctrl_type($params->{bug});
    };

    $self->{log_fh}->print("Source control type of this release $self->{utility_version} is $self->{src_ctrl_type}\n");
    

    $params->{action_desc} = 'Check Results';
    $log_fh->print_header($params->{action_desc});

    ($req_params) = ARUDB::single_row_query('GET_FARM_REQ_PARAMS',
        $params->{bug});

    foreach my $i (split('!', $req_params))
    {
        my ($key, $value) = split(':',$i);
        $farm_params{$key} = $value;
        $farm_params{lc($key)} = lc($value);

        $farm_params{lc($key)} = $value
            if (lc($key) eq "soa_topo");
    }

    my $farm = APF::PBuild::Farm->new(
            {bugfix_request_id => $bugfix_request_id,
             request_id        => $request_id,
             src_ctrl_type     => $self->{src_ctrl_type},
             log_fh            => $log_fh});

    $farm->checkFarmStatus(\%farm_params);

    $params->{farm_job_final_status} = $farm->{farm_job_final_status};
    $params->{farm_job_error_msg}    = $farm->{farm_job_error_msg};

    $params->{aru_no} = $params->{bugfix_request_id};
    $params->{ade_view_name} = $params->{aru_no};

    if ( $self->{gen_port} eq "O")
    {
        if (((!(exists($farm->{farm_internally_retried}))) && ($farm->{farm_internally_retried} != 1)) || $farm->{farm_job_final_status} =~ /\w+/)
        {
            $log_fh->print("DEBUG_FARM_45: Calling  _farm_postprocess_pse\n") ;
            $self->_farm_postprocess_pse($params);
            return;
        }
    }
    else
    {
        $farm->releasePSEs(\%farm_params);
    }
}


#
# BI components may span across multiple ARU/BugDB products.
# This is a convenience to return true if the product in question belongs to
# BI. Same subroutine exist in Base.pm
#
sub is_bi_product
{
  my ($self, $product_id) = @_;

  return 1 if (($product_id == APF::Const::product_id_obiee) or
               ($product_id == APF::Const::product_id_bifndnepm) or
               ($product_id == APF::Const::product_id_rtd) or
               ($product_id == APF::Const::product_id_bip));

  return 0;
}

#
# Retry request based on error criteria
# This is called after the request is marked as failed
#
sub retry_request {
  my ($self) = @_;

  my($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                                            $self->{request_id});


  if ($self->{pbdaemon_hash_file}) {
    eval {
      APF::PBuild::InstallTestUtil::dump_output_hash($self,
                                    $self->{pbdaemon_hash_file});
    };
  }

  my $params_hash = {};
  foreach my $token (split(/!/,$req_params)) {
    my ($h_key, $h_value) = split(/:/,$token);
    $params_hash->{$h_key} = $h_value;
  }

  my ($l_prefix, $l_req_id, $l_timestamp);
  if (exists $self->{log_fh}->{basename}) {
    ($l_prefix, $l_req_id, $l_timestamp) =
                  split(/_/,$self->{log_fh}->{basename});
  }

  my $request_hash;
  foreach my $h_key (keys %{$self->{request}}) {
    $request_hash->{$h_key} = $self->{request}->{$h_key};
  }
  delete($request_hash->{log});
  delete($request_hash->{trigger_log_fh});
  delete($request_hash->{trigger_log_file});

  my $error_details = $self->{failed_task_obj}->{failure}->{details};

  my $retry_req_obj = new APF::PBuild::RetryRequest (
                              work_area => $self->{aru_dir},
                         request_params => $params_hash,
                             request_id => $self->{request_id},
                          error_details => $error_details,
                              timestamp => $l_timestamp,
                                request => $request_hash,
                        );
  $retry_req_obj->{gen_or_port} = $self->{preprocess}->{gen_or_port};

  #
  # Hotfix to exclude HANDOVER requests from retrying
  # restructure later by adding patterns to apf_installtest_err_codes.pl
  #

  my $testname = $self->{testname} || $self->{err_msg} || "";
  if ($testname) {
    if ($testname =~ /Handing over the transaction|HANDOVER/) {
      if ($retry_req_obj->{log_fh}) {
        $retry_req_obj->{log_fh}->print("Handover request is not ".
                                        "marked for retry\n");
      }
      return;
    }
  }

  $retry_req_obj->process_request();
  $retry_req_obj->{log_fh}->close() if ($retry_req_obj->{log_fh});

}

sub send_parallel_proc_abort_alert
{
    my ($self, $backport_bug, $log_fh) = @_;

    my ($to, $cc, $all, $from, $subject, $body, $content_type);

    $content_type = APF::Config::farm_email_content_type;

    my ($bugdb_id) = ARUDB::single_row_query('GET_BASE_BUG_ASSIGNEE',
                                             $backport_bug);
    my ($valid) = ARUDB::single_row_query('IS_BUGDB_ID_VALID', $bugdb_id);
    $log_fh->print("DEBUG: Seding email alert : $backport_bug\n");

    if ($valid == 1)
    {
        ($to, $cc) = ARUDB::single_row_query('GET_MANAGER_EMAIL',
                                             uc($bugdb_id));

        $cc .= '@oracle.com';
        $to .= '@oracle.com';
    }
    else
    {
        $to = APF::Config::parallel_pses_abort_list;
        $cc = "";
    }

    $all = $to;
    #$all .= $cc if ($cc ne "");
    if ($cc ne "")
    {
        $all  = $all.",".$cc;
    }
    $from = ISD::Const::isd_do_not_reply;

    $body = "Hi,\n\nThere are PSE(s) waiting to get processed for BLR " .
            "$backport_bug. As the Farm job is failed, these PSE(s) can not be " .
            "processed and Patch processing is aborted. \n\n";

    $body .= "\n\n\nThank You.";
    $subject = "BLR $backport_bug failed and PSE(s) are waiting for the BLR ";

    #
    # FOR TESTING ONLY
    #

    if (ConfigLoader::runtime("development") ||
        ConfigLoader::runtime("sprint"))
    {
        $all = APF::Config::min_opatch_dev_contact_list;
        $cc = $all;

        $log_fh->print("\nSending:\n" .
                           "Subject:\t$subject\n" .
                           "To:\t$all\n" .
                           "\tMessage:\n$body\n");
    }

    $log_fh->print("DEBUG: email: $from, $to, $subject, $cc \n");

    my $mail_header = {
        'Reply-To'     => $from,
        'Subject'      => $subject,
        'From'         => $from,
        'Cc'           => $cc,
        'Content-type' => $content_type};

    $log_fh->print("\nSending mail as the Farm job is failed and the PSE(s) waiting ".
                   "to get processed for BLR $backport_bug : $all\n");

    ISD::Mail::sendmail($all, $mail_header, $body);

    return 1;
}

#
# Check is a request is eligible to run
# Suspend certain request types
#
sub _can_request_run {

  my ($self) = @_;

  my $grid_id = $self->{request}->{grid_id};
  my $request_type_code = $self->{request}->{type_code};
  my $host_name = PB::Config::short_host;

  $ENV{REQUEST_TYPE_CODE} = $request_type_code;

  my $config_file = $ENV{ISD_HOME} . "/conf/suspend_requests.pl";
  my $conf_obj = "";
  my %options;

  if (-e $config_file) {

    $conf_obj = ConfigLoader::include($config_file);
    my @attribs = ("all:all",
                   "request_types:$request_type_code",
                   "hosts:$host_name",
                   "grids:$grid_id");

    my $suspend_requests = $conf_obj->{suspend_requests};
    foreach my $attrib (@attribs) {
      my ($h_key, $h_value) = split(/:/,$attrib);
      if ($suspend_requests->{$h_key}->{$h_value}->{delay}) {
        $options{delay} =
            $suspend_requests->{$h_key}->{$h_value}->{delay};
        $options{mesg} =
          $suspend_requests->{$h_key}->{$h_value}->{message} ||
          "Suspending Request";
        $self->suspend(%options);
      }
    }
  }

  #
  # Check if bug# can be processed
  #
  my $bug = $self->{params}->{BUG} || $self->{params}->{bug};
  return if (!$bug);

  my @bugs;
  push(@bugs, $bug);

  my $aru = $self->{params}->{aru_no} || $self->{params}->{ARU_NO};
  if ($aru) {
    my $bug_aru_obj = new ARU::BugfixRequest($aru);
    $bug_aru_obj->get_details();
    push(@bugs, $bug_aru_obj->{bug}) if (exists $bug_aru_obj->{bug});
  }

  $config_file = $ENV{ISD_HOME} . "/conf/skip_bugs.pl";
  if (-e $config_file) {
    $conf_obj = ConfigLoader::include($config_file);
    my $bug_list = $conf_obj->{bug_list};
    foreach my $bug_no (@bugs) {
      if ($bug_list && 
          (grep(/$bug_no/, @{$bug_list}))) {
        $self->{log_fh}->print("bug $bug_no is in $config_file, ".
                               "aborting the current request\n") if ($self->{log_fh});
        my $l_user_id = ARU::Const::apf_userid;
        eval {
          ARUDB::exec_sp('isd_request.abort_request',
                         $self->{request_id},
                         $l_user_id,
                         "bug $bug_no is in $config_file, skipping");
        };
        exit APF::Const::exit_code_term;
      }
    }
  }
}

##############################################################################
# Name      : _farm_postprocess_pse
#
# Arguments : Self object and parameters passed while creating the request
#
#
# Returns: None
#
# Description:
# This subroutine helps to handle the postprocessing steps for the PSEs
# after submitting it to farm.
#
##############################################################################

sub _farm_postprocess_pse
{
    my ($self, $params) = @_;

    if ($params->{farm_job_final_status} eq "SUCCESS")
    {
         my($req_params) = ARUDB::single_row_query('GET_ST_APF_BUILD',
                      $self->{request_id});

         ARUDB::exec_sp('isd_request.add_request_parameter',
                         $self->{request_id},
                         "st_apf_build",$req_params.
                         "!suc:1");
    }

    $self->_post_process_branched_txn($params);
}

#
# On Success trigger for house keeping activities
# This method is called for all successful requests
#

sub on_success {
  my ($self) = @_;

  if ($self->{request}->{req_status_file}) {
    my $new_req_status_file = $self->{request}->{req_status_file};
    $new_req_status_file =~ s/.running|.failed|.suspended/.success/g;
    if (-e $self->{request}->{req_status_file}) {
      my $cmd = "mv $self->{request}->{req_status_file} $new_req_status_file";
      `$cmd`;
    }
  }

  #
  #  Cleanup SSH Cache files
  #
  my $cmd;
  my $base_work = PB::Config::apf_base_work;
  my $ssh_cache_dir = dirname($base_work) .  "/.ssh_pool_cache";
  my $aru = $self->{aru_obj}->{aru} || $self->{params}->{ARU_NO};
  eval {
    if ($aru) {
      my $ssh_lock_file = $ssh_cache_dir . "/.*_" . $aru;
      $cmd = "ls ${ssh_lock_file}";
      my @ls_cmd = `$cmd 2>/dev/null`;
      foreach my $lfile (@ls_cmd) {
        chomp($lfile);
        `unlink $lfile` if (-e $lfile);
      }
    }
  };
  $self->cleanup_spb_patch() if($self->{preprocess}->{type} eq "stackpatch");
}

#
#Cleanup SPB Patch workarea patch content includes .zip file and readme files
#
sub cleanup_spb_patch {

    my ($self) = @_;
    my $preprocess = $self->{preprocess};
    my $reference_id = $self->{request}->{reference_id};
    $reference_id = $preprocess->{BUG} unless ($reference_id);
    my $fh= new FileHandle(">> cleanupspb.txt");
    $fh->print('*' x 100, "\n\n");
    $fh->print("bug $preprocess->{bug} \n");
    $fh->print("platform_id $preprocess->{platform_id} \n");
    $fh->print("release_id $preprocess->{release_id} \n");
    $fh->print("product_id $preprocess->{product_id} \n");
    $fh->print("reference_id $reference_id \n");

    return  unless($preprocess->{type} eq "stackpatch");
    my ($aru) = ARUDB::single_row_query('GET_ARU',$preprocess->{bug},
                $preprocess->{platform_id},$preprocess->{release_id},
                $preprocess->{product_id});
    # return unless($aru);
    my $common_path = $self->{preprocess}->{base_work};
    my @isd_requests = ARUDB::query('GET_ISD_REQ_BY_REF_ID',$reference_id);
    foreach my $row (@isd_requests){
        my ($request_id) = $row->[0];
        my $path = "$common_path/$request_id";
        $fh->print("path $path \n");

        my $cmd = "rm -r $path/$preprocess->{bug}* $path/README.*";
        $fh->print('*' x 100, "\n\n");
        $fh->print("command $cmd");

    # `$cmd`;
    }
    $fh->print('*' x 100, "\n\n");
    $fh->print(Dumper($preprocess));
    $fh->close();
}


#
# On failure trigger for house keeping activities
# This method is called for all failed requests
#
sub on_failure {
  my ($self) = @_;
print('RCHAMANT ON FAILURE' x 100, "\n\n");
my $fh= new FileHandle(">> on_failure.txt");
$fh->print('*' x 100, "\n\n");
$fh->print(Dumper($self));
$fh->close();
  my $cmd = "";
  if ($self->{request}->{req_status_file}) {
    my $new_req_status_file = $self->{request}->{req_status_file};
    $new_req_status_file =~ s/.running|.success|.suspended/.failed/g;
    if (-e $self->{request}->{req_status_file}) {
      $cmd = "mv $self->{request}->{req_status_file} $new_req_status_file";
      `$cmd`;
    }
  }

  #
  #  Cleanup SSH Cache files
  #
  my $base_work = PB::Config::apf_base_work;
  my $ssh_cache_dir = dirname($base_work) .  "/.ssh_pool_cache";
  my $aru = $self->{aru_obj}->{aru} || $self->{params}->{ARU_NO};
  eval {
    if ($aru) {
      my $ssh_lock_file = $ssh_cache_dir . "/.*_" . $aru;
      $cmd = "ls ${ssh_lock_file}";
      my @ls_cmd = `$cmd 2>/dev/null`;
      foreach my $lfile (@ls_cmd) {
        chomp($lfile);
        `unlink $lfile` if (-e $lfile);
      }
    }
  };

  #
  # Record reason for failure in isd_request_parameters
  # for analysis
  #
  eval {
    my $err_code =
          $self->{failed_task_obj}->{failure}->{details}->{err_code} || "";

    my $host_name = PB::Config::short_host;
    my $worker_host = $self->{failed_task_obj}->{wkr_host} || "";

    my $failure_info = "$host_name:$worker_host:$err_code";

    APF::PBuild::Util::update_req_parameters($self->{request_id},
                                             "failure_details", $failure_info,
                                             "", "yes");
  };

    $self->cleanup_spb_patch() if($self->{preprocess}->{type} eq "stackpatch");

}
#
# Generate Gold Image
#
sub _create_goldimage {
  my ($self, $params) = @_;

  my $action_desc = "Generate Gold Image";
  if ($params->{db_psu}) {
    $action_desc .= " - " . "dbPSU: " . $params->{db_psu};
  }

  if ($params->{gi_psu}) {
    if ($action_desc eq "Generate Gold Image") {
      $action_desc .= " - " . "giPSU: " . $params->{gi_psu};
    } else {
      $action_desc .= ", " . "giPSU: " . $params->{gi_psu};
    }
  }

  $self->{aru_log}->print_header($action_desc)
                              unless($self->skip_header($params));
  $params->{release} = uc($params->{release});
  my $goldimage_obj = new APF::PBuild::GoldImage({
                                        bugfix_req_id => $params->{psu_aru},
                                        request_id    => $self->{request_id},
                                        log_fh        => $self->{aru_log},
                                        params        => $params});

  $goldimage_obj->create_goldimage();
}

#
# Routine to seed used kspares into kspare tool
#
sub _seed_kspares
{
    my ($self, $params) = @_;

    $self->{log_fh}->print_header("Seed Kspares");
    my $obj = new APF::PBuild::KspareUpdates($params);
    $obj->process();
}

#
# Routine to retry the CIs which did not find source txn
# and still in triage (51/PSEREP) queue
#
sub _queue_ci
{
    my ($self, $params) = @_;

    my ($tmp) = ARUDB::exec_sf('aru_parameter.get_parameter_value',
                    'QUEUE_CI_REQUEST_DELAY');
    my ($delay, $mod_val, $mod) = split(':', $tmp);
    my $retry = 0;

    my $data = "";

    eval
    {
        ($data) = ARUDB::exec_sf(
                    'aru_parameter.get_parameter_value',
                    'BACKPORT_CI_RETRY_QUEUE');
    };

    eval
    {
        $self->{log_fh}->print_header("Retry CI");
        my $obj = new APF::PBuild::BackportUtils(
                  $self->{log_fh}, $params->{request_id});
        $retry = $obj->queue_ci($data, $delay, $mod_val, $mod);
    };

    if ($@)
    {
        $retry = 1;
        my $prevData = $data;
        $data = "";
        eval
        {
            ($data) = ARUDB::exec_sf(
                      'aru_parameter.get_parameter_value',
                      'BACKPORT_CI_RETRY_QUEUE');
        };

        $prevData .= ",$data" if ($data ne "");

        ARUDB::exec_sp('aru_parameter.set_parameter',
                       'BACKPORT_CI_RETRY_QUEUE',
                       $prevData,
                       "Queue of CI bugs with no-src-txn",
                       $prevData);
    }

    #
    # Retry the request after an delay
    #
    if ($retry == 1)
    {
        my $comments = "CI retry request, dealyed by $delay seconds";
        my @data = ({name => 'p_request_id',
                     data => $self->{request_id}},
                    {name => 'p_delay',
                     data => $delay},
                    {name => 'p_comments',
                     data => $comments});

        ARUDB::exec_sp("isd_request.requeue_request", @data);
    }
}

#
# Build oneoff patches
#
sub _build_oneoff {
  my ($self, $params) = @_;

  my $action_desc = "Build oneoff";
  $self->{aru_log}->print_header($action_desc)
                              unless($self->skip_header($params));

  my $oneoff_obj = new APF::PBuild::BuildOneoff({
                                        request_id    => $self->{request_id},
                                        log_fh        => $self->{aru_log},
                                        params        => $params});
  $oneoff_obj->process_request();
}

1;

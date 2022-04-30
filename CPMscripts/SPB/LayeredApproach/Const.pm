#
# DO NOT MODIFY THIS FILE!!!!!!!
#
# This file is generated automatically by .git/hooks/constants.pl. It is
# based on the contents of isd/plsql/aru/aru_constants.pls. To add a
# constant, edit that file and run .git/hooks/constants.pl aru
#

package ARU::Const;

use strict;
require 5.005;

# Constants generated from isd/plsql/aru/aru_constants.pls


#
# Copyright (c) 2010, 2015 by Oracle Corporation. All Rights Reserved.
# Header: aru_constants.pls@@/main/148 \
# Checked in on Fri May 28 06:57:25 PDT 2010 by rkada \
# Copyright (c) 2002, 2010 by Oracle Corporation. All Rights Reserved. \
# $
#

   #
   # ARU and APF userids
   #
use constant aru_userid                => 1;
use constant apf_userid                => 353;
use constant apf2_userid               => 5;
use constant apfrl_userid              => 7;
use constant nls_wkr_userid            => 6713;
use constant epd_userid                => 2;

   #
   # Bugfix request (ARU) statuses
   #
use constant patch_requested                 => 5;
use constant patch_full_trans_avlbl          => 20;
use constant patch_ftped_support             => 22;
use constant patch_ftped_dev                 => 23;
use constant patch_ftped_dev_qa              => 27;
use constant patch_ftped_internal            => 24;
use constant patch_downloaded                => 25;
use constant patch_partially_built           => 26;
use constant patch_test_deleted              => 30;
use constant patch_test_aborted              => 31;
use constant patch_denied                    => 35;
use constant patch_denied_empty_payload      => 953;
use constant patch_denied_no_aru_patch       => 954;
use constant patch_skipped                   => 956;
use constant ready_to_ftp_to_support         => 957;
use constant ready_to_ftp_to_dev             => 958;
use constant patch_nothing_to_translate      => 40;
use constant patch_on_hold                   => 45;
use constant patch_queued_for_postprocess    => 50;
use constant patch_mgr_preprocess            => 52;
use constant patch_code_pull_failure         => 55;
use constant patch_ftp_to_wkr_failure        => 57;
use constant patch_queued_for_worker         => 58;
use constant patch_wkr_processing            => 59;
use constant patch_ftp_from_wkr_failure      => 60;
use constant patch_code_build_failure        => 62;
use constant patch_mgr_postprocess           => 64;
use constant patch_ftp_to_repos_failure      => 65;
use constant patch_verification_failure      => 67;
use constant patch_attempt_ftp_to_wkr        => 68;
use constant patch_attempt_ftp_from_wkr      => 69;
use constant patch_attempt_ftp_to_repos      => 70;
use constant patch_comment_change            => 118;
use constant patch_priority_updated          => 1536;
use constant patch_q_delete                  => 205;
use constant patch_deleted                   => 206;
use constant patch_q_transfer                => 207;
use constant patch_attempt_delete            => 208;
use constant patch_attempt_transfer          => 209;
use constant patch_deleting                  => 210;
use constant patch_transferring              => 211;
use constant patch_queued_for_nlswkr         => 910;
use constant patch_nls_wkr_evaluating        => 912;
use constant patch_nls_wkr_preprocess        => 915;
use constant patch_queued_for_translation    => 918;
use constant patch_nls_wkr_transl_inprogres  => 920;
use constant patch_queued_for_nls_wkr_postp  => 924;
use constant patch_nls_wkr_postprocess       => 925;
use constant patch_nls_wkr_failure           => 940;
use constant patch_nls_wkr_processing        => 16;
use constant patch_nls_wkr_deferred          => 950;
use constant patch_queued_for_create_tkit    => 921;
use constant patch_creating_tkit             => 922;
use constant patch_queued_for_tkit_merge     => 926;
use constant patch_merging_tkit              => 927;
use constant patch_queued_for_final_lvrg     => 936;
use constant patch_final_leveraging          => 937;
use constant patch_creating_tkit_failure     => 942;
use constant patch_translations_incomplete   => 943;
use constant patch_merging_tkit_failure      => 944;
use constant patch_final_leverage_failure    => 946;
use constant patch_nls_wkr_preproc_failure   => 917;
use constant patch_replaced                  => 919;
use constant patch_online_failure            => 444;
use constant patch_online_success            => 443;
use constant patch_unobfuscated_security     => 947;
use constant patch_translation_completed     => 951;
use constant patch_build_deferred            => 948;
use constant patch_build_pending             => 938;
use constant patch_translation_pending       => 949;
use constant patch_translation_failure       => 41;

   #
   # Bugfix Request (ARU) statuses for EPD.
   #
use constant patch_not_supported           => 865;
use constant patch_enabled                 => 870;
use constant patch_disabled                => 875;

   #
   # Statuses for EPD Japan and EPD Linux for bugfix attributes
   #
use constant epd_model                     => 20019;
use constant epd_model_global              => 20020;
use constant epd_model_japan               => 20021;
use constant epd_model_linux               => 20029;
use constant epd_model_smb                 => 20036;

   #
   # Statuses for aru_user_attributes
   #
use constant epd_customer_order_num        => 35500;
use constant language                      => 11001;
use constant access_type                   => 35551;
use constant epd_delegated_by              => 35552;
use constant access_time                   => 35553;

   #
   # access types for Web Sevices
   #
use constant access_type_epd               => 'E';

   #
   # State of file in aru_files
   #
use constant file_state_exists             => 'E';
use constant file_state_removed            => 'R';
use constant file_state_not_uploaded       => 'N';
use constant file_state_uploaded_by_apfrl  => 'L';
   #
   # ARU File Digest Group code
   #
use constant file_digest_group             => 353;

   #
   # Tkit statuses
   #
use constant tkit_created                  => 485;
use constant tkit_uploaded                 => 486;
use constant tkit_downloaded               => 487;
use constant tkit_deleted                  => 488;
use constant tkit_merged                   => 490;
use constant tkit_ignored                  => 491;
use constant tkit_manually_merged          => 492;
use constant tkit_obsolete                 => 495;

   #
   # Hyperhub releated
   #
use constant hyperhub_leverage             => 470;
use constant hyperhub_createtk             => 475;
use constant hyperhub_mergetk              => 480;

use constant hyperhub_success              => 61000;
use constant hyperhub_timeout              => 61050;
use constant hyperhub_db_error             => 61061;
use constant hyperhub_rmiregistry_error    => 61062;
use constant hyperhub_tmpdb_error          => 61063;
use constant hyperhub_failure              => 61064;
use constant hyperhub_coord_error          => 61065;
use constant hyperhub_coord_lookup_error   => 61066;
use constant hyperhub_rmi_connect_error    => 61082;
use constant hyperhub_unleverage           => 62011;
use constant hyperhub_no_tkit              => 62110;
use constant hyperhub_missing_bom          => 62169;
use constant hyperhub_invalid_bom          => 62180;
use constant hyperhub_missing_file         => 62066;
use constant hyperhub_file_not_readable    => 61080;
use constant hyperhub_missing_archive      => 62264;
use constant hyperhub_merge_maxlen_error   => 62286;
use constant hyperhub_invalid_logfile      => 62288;
use constant hyperhub_logfile_not_found    => 62289;
use constant hyperhub_trans_incomplete     => 62290;
use constant hyperhub_untrans_words        => 62291;
use constant hyperhub_invalid_zipfile      => 62263;
use constant hyperhub_tempdb_down          => 65046;
use constant hyperhub_invalid_project      => 62265;
use constant hyperhub_invalid_utf8_encode  => 62285;
use constant hyperhub_missing_datfile      => 62293;
use constant hyperhub_mergetk_invalid_utf8 => 66285;
use constant hyperhub_mergetk_test_fail    => 66301;

   #
   # aru_filestores table status ids.
   #
use constant filestore_wait                => 800;
use constant filestore_in                  => 801;
use constant filestore_empty               => 802;
use constant filestore_bad                 => 803;
use constant filestore_leveraged           => 804;
use constant filestore_releverage          => 805;
use constant filestore_releverage_fail     => 806;


   #
   # Release Baselines
   #
use constant release_baseline              => 121;
use constant product_release_baseline      => 122;
use constant release_generic               => 90000000;

   #
   # Release Types
   #
use constant upload_release_type           => 'aBMuv';
use constant fusion_type_rel               => 'AaBDPQLVvus';

   #
   # Instance Status Codes
   #
use constant apf_instance_v1_compatible    => 109;
use constant apf_instance_disabled         => 110;
use constant apf_instance_online           => 111;
use constant apf_instance_offline          => 112;
use constant apf_instance_down             => 113;

   #
   # APF Grid Identifiers.
   #
use constant apf_grid_disabled             => 'APF_GRID_DISABLED';
use constant apf_grid_offline              => 'APF_GRID_OFFLINE';

   #
   # APF type
   #
use constant apf_manager_type              => 'M';
use constant apf_worker_type               => 'W';
use constant nls_worker_type               => 'N';
use constant apf_repository_loader_type    => 'R';

   #
   # APF processing actions.
   #
use constant apf_action_preprocess         => 'preprocessing';
use constant apf_action_postprocess        => 'postprocessing';
use constant apf_action_process            => 'processing';
use constant apf_action_delete             => 'delete';
use constant apf_action_rename             => 'rename';
use constant apf_action_transfer           => 'transfer';
use constant apf_action_gen_mxml           => 'gen_mxml';
use constant apf_action_upload             => 'upload';
use constant apf_action_resume             => 'resume';
use constant apf_action_worker_pull        => 'worker_pull';
use constant apf_action_final_leverage     => 'final_leverage';
use constant apf_action_create_tkit        => 'create_tkit';
use constant apf_action_cleanup            => 'cleanup';


   #
   # Auto-request type
   # request_enabled column in table apf_configurations
   #
use constant auto_req_base_us           => 'B';
use constant auto_req_generic_us        => 'G';
use constant auto_req_hipo_checkin      => 'H';
use constant auto_req_nls_full          => 'L';
use constant auto_req_disabled          => 'N';
use constant auto_req_non_base_us       => 'P';
use constant auto_req_checkin_rel       => 'R';
use constant auto_req_nls_pseudo        => 'S';
use constant auto_req_enabled           => 'Y';

   #
   # Porting required status
   #
use constant requires_porting           => 'Y';
use constant not_requires_porting       => 'N';

   #
   # Bugfix Relationships
   #
use constant included_direct               => 601;
use constant skipped_included              => 627;
use constant included_indirect             => 602;
use constant included_implicit             => 607;
use constant prereq_direct                 => 603;
use constant prereq_indirect               => 604;
use constant postreq_direct                => 625;
use constant postreq_indirect              => 626;
use constant prereq_cross_direct           => 605;
use constant prereq_cross_indirect         => 606;
use constant dropped_prereq_over_repl      => 608;
use constant build_only_prereq_direct      => 611;
use constant build_only_prereq_indirect    => 612;
use constant fusion_coreq_recommended      => 661;
use constant fusion_coreq_required         => 662;
use constant fusion_coreq_reco_indirect    => 663;
use constant fusion_coreq_reqd_indirect    => 664;

use constant fixed_direct                  => 609;
use constant fixed_indirect                => 610;
use constant fixed_direct_others           => 613;
use constant fixed_direct_pse              => 614;

use constant replacement_original          => 620;
use constant replacement_latest            => 630;
use constant intended_include              => 615;
use constant intended_remove               => 616;
use constant based_on                      => 640;
use constant baseline_intro_direct         => 650;
use constant baseline_intro_indirect       => 660;

   #
   # Relationship to mark the release introduced by PSU.
   #
use constant psu_introducing_release       => 617;

   #
   # Overlay for ST patch.
   #
use constant overlay_direct                => 618;

   #
   # N-Apply bundle molecule
   #
use constant molecule_direct                => 619;

   #
   # Relation ship for copied transactions
   #
use constant transaction_copied_from        => 621;

   #
   # Forwardport bug constants
   #
use constant forwardport_mainline          => 670;
use constant forwardport_branchline        => 680;
use constant forwardport_placeholder_bug   => 999999999;

   #
   # Composite constituent constants
   #
use constant composite_constituents        => 690;
use constant fixed_indirect_composite      => 691;


   # Relation types
   #
use constant self_relation                 => 700;
use constant direct_relation               => 701;
use constant indirect_relation             => 702;

   #
   # Checkin Dependency access
   #
use constant bugfix_includable              => 710;
use constant bugfix_prereqable              => 720;
use constant bugfix_to_include_prereq       => 730;
use constant bugfix_not_to_include_prereq   => 740;

   #
   # Techstack Prereq
   #
use constant techstack_prereq               => 750;

   #
   # Inclusion Request Patch Category
   #
use constant incl_patch_category_group        => 7010;
use constant incl_patch_category_functional   => 7020;
use constant incl_patch_category_install      => 7030;
use constant incl_patch_category_ihelp        => 7040;


   #
   # Dependency Rule statuses
   #
use constant rule_active                    => 'ACTIVE';
use constant rule_inactive                  => 'INACTIVE';

   #
   # Checkin Statuses
   #
use constant checkin_updated               => 71;
use constant checkin_progress              => 72;
use constant checkin_released              => 73;
use constant checkin_released_hipo         => 75;
use constant checkin_obsoleted             => 74;
use constant checkin_priority_raised       => 155;
use constant checkin_priority_lowered      => 156;
use constant checkin_metadata_updated      => 157;
use constant checkin_readme_updated        => 158;
use constant checkin_superseded            => 280;
use constant in_progress_checkin_updated   => 1200;
use constant released_checkin_updated      => 1201;
use constant checkin_commit_failed         => 1205;
use constant checkin_on_hold               => 290;
use constant checkin_approved              => 166;
use constant checkin_replacement_pending   => 295;
use constant checkin_replaced              => 296;

   #
   # Checkin Events
   #
use constant checkin_evt_defn_updated      => 159;
use constant checkin_evt_opened            => 161;
use constant checkin_evt_closed            => 162;
use constant checkin_evt_released          => 163;
use constant checkin_evt_superseded        => 164;
use constant checkin_evt_obsoleted         => 165;
use constant checkin_evt_locked            => 167;
use constant checkin_evt_unlocked          => 168;
   #
   # Checkin History Actions
   #
use constant action_inserted               => 'I';
use constant action_deleted                => 'D';
use constant action_updated                => 'U';
use constant action_placeholder            => '-';

   #
   # Error code for perl subroutines returns.
   #
use constant return_error                 => 2;
use constant return_warn                  => 1;

   #
   # Checkin state Actions
   #
use constant checkin_state_outdated         => 'O';
use constant checkin_state_locked           => 'L';
use constant checkin_state_invalid          => 'I';
use constant checkin_state_msi_outdated     => 'M';

   #
   # aru_unlimited_text
   #
use constant text_data_limit                => 2000;

   #
   # CLI and Transaction checkin flags.
   #
use constant cli_checkin                   => 35308;
use constant transaction_checkin           => 35309;

   #
   # Branch level label
   #
use constant branch_label                  => 35316;

   #
   # Tier1 Support Date
   #
use constant ebs_tier1_date                => 95516;
   #
   # MEP integration flags.
   #
use constant promote_txn_aru               => 35318;
use constant invoked_by_cron               => 35320;

use constant ade_label                     => 35325;
use constant ade_transaction               => 35326;
use constant ade_dep_label                 => 35327;
use constant ade_dep_fa_label              => 35328;
use constant translation_type              => 35335;
use constant translation_requests          => 45335;

use constant pbuild_checkin                => 35330;
use constant bundle_type                   => 35336;

use constant mandatory_patch               => 35600;

   #
   # Msi step type_id
   #
use constant required                 => 35311;
use constant recommended              => 35312;
use constant optional                 => 35313;
use constant conditional              => 35314;
use constant informational            => 35315;
use constant other                    => 407;

   #
   # Composite patch
   #
use constant composite_patch         => 35340;

   #
   # System Patch Bundle Types. Value refers to aru status code
   #
use constant system_patch            => 35350;
use constant bundle_patch            => 34501;
use constant system_bundle_types     => 1234;
use constant system_sub_patch        => 696;

   # Default value for codeline independent patches
   #
use constant default_codeline               => 'MainLine';

   #
   # GSCC Standard IDs
   #
use constant gscc_id_file_c_5               => 2035;
use constant gscc_id_file_form_5            => 2037;
use constant gscc_id_file_gen_11            => 2036;
use constant gscc_id_file_java_29           => 2038;
use constant gscc_id_file_c_7               => 2837;


   #
   # GSCC Responsibility
   #
use constant gscc_administrator             => 6217;

   #
   # GSCC Statuses
   #
use constant gscc_error_type_all            => 10999;
use constant gscc_error_type_warning        => 10000;
use constant gscc_error_type_error          => 10001;
use constant gscc_error_type_warning2       => 10099;
use constant gscc_status_enabled            => 10003;
use constant gscc_status_disabled           => 10004;
use constant gscc_status_proposed           => 10005;
use constant gscc_status_rejected           => 10006;
use constant gscc_status_deprecated         => 10007;
use constant gscc_status_bug_in_efc         => 10008;
use constant gscc_status_in_development     => 10009;
use constant gscc_efc_status_enforced       => 10010;
use constant gscc_efc_status_disabled       => 10011;
use constant gscc_efc_status_not_feasible   => 10012;
use constant gscc_error_type_na             => 10013;
use constant gscc_error_type_under_review   => 10077;
use constant gscc_efc_status_database_check => 10079;
use constant gscc_efc_status_derived_check  => 10080;
use constant gscc_efc_enforced_in_scs       => 10093;
use constant gscc_efc_enforced_in_apf       => 10094;
use constant gscc_code_review_requested     => 10082;
use constant gscc_code_review_canceled      => 10083;
use constant gscc_code_review_approved      => 10084;
use constant gscc_code_review_rejected      => 10085;
use constant gscc_code_review_auto_pass     => 10086;
use constant gscc_code_review_pr_approved   => 10110;
use constant gscc_code_review_pfr_approved  => 10111;
use constant gscc_bypass_unresolved         => 10087;
use constant gscc_bypass_resolved           => 10088;
use constant gscc_bypass_canceled           => 10089;
use constant gscc_code_review               => 10090;
use constant gscc_bypass                    => 10091;
use constant gscc_efc_bugfix_status         => 10092;
use constant gscc_env_standard_category     => 10095;
use constant gscc_efc_enforced_by_jaudit    => 10100;
use constant gscc_bugfix_not_checked        => 1010;
use constant gscc_bugfix_fail               => 1020;
use constant gscc_bugfix_dated_warn         => 1030;
use constant gscc_bugfix_warn               => 1040;
use constant gscc_bugfix_pass               => 1050;
use constant gscc_engine_failure            => 1060;
use constant gscc_bugfix_exempt             => 1070;
use constant gscc_bugfix_dwe_exception      => 1080;
use constant gscc_bugfix_we_exception       => 1090;
use constant gscc_bugfix_wdw_exception      => 1100;
use constant gscc_bugfix_dwdw_exception     => 1110;
use constant gscc_bugfix_unknown            => 1120;
use constant gscc_bugfix_p1_bypass          => 1130;

   #
   # GSCC Open EFC
   #
use constant gscc_efc_to_test_os_efc      => 'File.Perl.3';

   #
   # GSCC Engine phases
   #
use constant gscc_phase_source             => 'SOURCE';
use constant gscc_phase_derived            => 'DERIVED';
use constant gscc_phase_msi                => 'MSI';

   #
   # GSCC Result Set filter_id
   #
use constant gscc_base_result_filter_id                    => 0;
use constant gscc_bugfix_base_filter_id                    => 1;
use constant gscc_obj_gfather_filter_id                    => 3;
use constant gscc_obj_ver_gfather_filter_id                => 4;
use constant gscc_code_review_filter_id                    => 5;
use constant gscc_p1_bypass_filter_id                      => 6;
use constant gscc_obj_excep_filter_id                      => 7;
use constant gscc_prod_base_filter_id                      => 8;
use constant gscc_pseudo_base_filter_id                    => 9;
use constant gscc_prod_obj_gf_filter_id                    => 10;
use constant gscc_pseudo_obj_gf_filter_id                  => 11;
use constant gscc_prod_ver_gf_filter_id                    => 12;
use constant gscc_pseudo_ver_gf_filter_id                  => 13;
use constant gscc_prod_bugfix_filter_id                    => 14;
use constant gscc_pseudo_bugfix_filter_id                  => 15;
use constant gscc_final_result_filter_id                   => 100;

   #
   # Platform IDs
   #
use constant platform_solaris              => 453;
use constant platform_test                 => 888;
use constant platform_windows              => 176;
use constant platform_windows64            => 233;
use constant platform_generic_bugdb        => 289;
use constant platform_generic              => 2000;
use constant platform_linux                => 46;
use constant platform_tru64                => 87;
use constant platform_aix                  => 319;
use constant platform_hpux                 => 999;
use constant platform_hpux_ia              => 197;
use constant platform_nls_wkr              => 1234;
use constant platform_nls_partial          => 2234;
use constant platform_nls_pseudo           => 3234;
use constant platform_solaris64            => 23;
use constant platform_aix5l                => 212;
use constant platform_hpux64               => 59;
use constant platform_hpux32               => 2;
use constant platform_linux64              => 110;
use constant platform_linux64_amd          => 226;
use constant platform_zlinux               => 209;
use constant platform_linux_itanium        => 214;
use constant platform_hp_openvms_alpha     => 89;
use constant platform_hp_openvms_itanium   => 243;
use constant platform_fj_bs2000_sseries  => 361;
use constant platform_fj_bs2000_sxseries => 285;
use constant platform_metadata_only      => 99999;

   #
   # These are obsolete and should not be used. Use the constants above.
   #
use constant solaris_platform              => 453;
use constant ms_windows_nt_server          => 912;
use constant generic_platform              => 2000;

   #
   # Platform Admin Prefix
   #
use constant platform_admin => 'Platform Admin';

   #
   # Patchset statuses  status_id for a patchset that is open
   #
use constant pset_open                     => 76;
use constant pset_closed                   => 77;
use constant pset_released                 => 78;
use constant pset_superseded               => 79;
use constant pset_updated                  => 80;
use constant pset_obsoleted                => 81;
use constant pset_private                  => 90;


   # Constant to identify mainline patch
   # This is used for the baselines dropdown while checkin creation.
   #
use constant mainline_patch        => 1;

   #
   # Prefix used to identify a private checkin.
   #
use constant private_checkin_prefix        => 9;

   #
   # Suffix used to identify a private patchset checkin.
   #
use constant private_pset_suffix           => '*';

   #
   # Public, Private checkin identifiers
   #
use constant public_checkin                => 'public';
use constant private_checkin               => 'private';


   #
   # Patchset request statuses
   #
use constant approved                      => 250;
use constant included                      => 260;
use constant rejected                      => 270;

   #
   # patch type constants
   #
use constant ptype_automated_build         => 95;
use constant ptype_candidate               => 96;
use constant ptype_standalone              => 97;
use constant ptype_standard                => 98;
use constant ptype_patchset                => 99;
use constant ptype_doc_standard            => 100;
use constant ptype_doc_standalone          => 101;
use constant ptype_doc_candidate           => 102;
use constant ptype_debug                   => 200;
use constant ptype_first_time_translation  => 103;
use constant ptype_platform_migration      => 104;
use constant ptype_doc_first_time_trans    => 105;
use constant ptype_trans_sync              => 106;
use constant ptype_egroup                  => 197;
use constant ptype_epack                   => 198;
use constant ptype_epart                   => 199;
use constant ptype_bundle                  => 152;
use constant ptype_cumulative_build        => 153;
use constant ptype_merged                  => 154;
use constant ptype_diagnostic              => 81000;
use constant ptype_meta_data               => 2;
use constant ptype_name_patch              => 'Patch';
use constant ptype_name_patchset           => 'Patchset';

   #
   # Distribution Statuses
   # The distribution statuses may look confusing, but there is history
   # behind this confusion. When originally created dist_support was
   # a constant representing the status 'By Support', but later this was
   # renamed to 'By Metalink'. But the constant name was not changed
   # as this required changes in many packages.
   # Later, again 'By Support' was introduced, as another support status,
   # but the constant name dist_support was already being used by
   # 'By Metalink'; hence created a constant called dist_metalink.
   # To use the new distribution status 'By Support' in the transition
   # phase, a new constant was introduced dist_support_temp (225).
   # Hope some day we will switch these constants and live in peace.
   #
use constant dist_none                     => 201;
use constant dist_development              => 202;
use constant dist_metalink                 => 203;
use constant dist_support                  => 203; # (dist_metalink)
use constant dist_m_and_d                  => 204;
use constant dist_support_temp             => 225;
use constant dist_epd                      => 212;
use constant dist_ready_to_support         => 214;
use constant dist_ready_to_dev             => 215;

   #
   # Products
   #
use constant product_au                    => 127;
use constant product_ad                    => 100;
use constant product_atg_pf                => 9340;
use constant product_fnd                   => 101;
use constant product_txk                   => 11422;
use constant product_epd                   => 12000;
use constant product_ora_apps              => 5;
use constant product_db_n_tools            => 10;
use constant product_misc                  => 15;
use constant product_ebiz                  => 126;
use constant product_bugdb_aru             => 1057;
use constant product_application_install   => 166;
use constant product_oracle_database       => 9480;
use constant product_oracle_app_server     => 10120;
use constant product_smp_pf                => 9800;
use constant product_emgrid                => 12383;
use constant product_emdbc                 => 12384;
use constant product_iagent                => 9801;
use constant product_bea_pf                => 15384;
use constant product_beaalbpm              => 15948;
use constant product_bugdb_emgrid          => 1370;
use constant product_bugdb_emias           => 1369;
use constant product_bugdb_emdbc           => 1366;
use constant product_bugdb_oracle_forms    => 45;
use constant product_bugdb_oid             => 355;
use constant product_bugdb_oracle_reports  => 159;
use constant product_bugdb_beaowls         => 5242;
use constant product_bugdb_p4fa            => 10633;
use constant product_ogg_ggate             => 16808;
use constant product_oim_excp_bkp          => 1981;
use constant product_wls_excp_bkp          => 5243;


   #
   # Product Abbreviations
   #
use constant product_abbr_au               => 'au';
use constant product_abbr_txk              => 'txk';
use constant product_abbr_fnd              => 'fnd';


   #
   # Bug database product suite mappings
   #
use constant bug_applications_suite        => 5;
use constant bug_application_server_suite  => 10120;
use constant bug_database_suite            => 9480;
use constant bug_collaboration_suite       => 11603;
use constant bug_enterprise_manager_suite  => 12965;
use constant bug_business_units            => 15;
use constant bug_fusion_applications_suite => 15405;

   #
   # Product Types
   #
use constant product_type_regular          => 'R';
use constant product_type_pseudo           => 'P';
use constant product_type_family           => 'F';
use constant product_type_group            => 'G';
use constant product_type_product          => 'P';
use constant product_type_extension        => 'X';
use constant product_type_any              => 'any_product';

   #
   # Contact Type Main Identifiers
   #
use constant contact_type_main           => 'M';
use constant contact_type_alternate      => 'A';

   #
   # Access groups
   #
use constant access_request_aru               => 1;
use constant access_update_aru                => 2;
use constant access_aru_checkin               => 3;
use constant access_chg_chkn_priority         => 4;
use constant access_download_patch            => 5;
use constant access_define_patchsets          => 6;
use constant access_download_dev_patches      => 13;
use constant access_download_prod_patches     => 14;
use constant access_support_group             => 17;
use constant access_account_admin             => 19;
use constant access_download_unrel_patches    => 33;
use constant access_nlsftpd                   => 34;
use constant access_nls_administration        => 16;
use constant access_release_aru               => 38;
use constant access_epd_admin                 => 36;
use constant access_epd_export_screening      => 37;
use constant access_epd_license_list          => 42;
use constant access_epd_download_tracker      => 44;
use constant access_update_dep_rules          => 45;
use constant access_req_released_internal     => 43;
use constant access_request_not_distributed   => 21;
use constant access_req_by_dev_patches        => 22;
use constant access_pkm                        => 8;
use constant access_patch_upload               => 25;
use constant access_master_upload              => 26;
use constant access_update_aru_priority        => 11;
use constant access_update_aru_status          => 10;
use constant access_update_epd_aru_status      => 48;
use constant access_md_downloads_pwd_access => 41;
use constant access_aru_administration           => 7;
use constant access_customer_identy_access     => 39;
use constant access_upd_epd_aru_status   => 48;
use constant access_epd_upd_patches      => 49;
use constant access_epd_rls_patches      => 50;
use constant access_gscc_prod_administrator    => 46;
use constant access_gscc_administration        => 32;
use constant access_gscc_rel_administrator     => 55;
use constant access_start_apf_worker           => 51;
use constant access_update_contacts            => 52;
use constant access_update_chkin_dependency   => 'Update Checkin Dependency';
use constant access_pset_maintenance          => 'Patchset Maintenance';
use constant access_upd_released_chkins       => 'Update Released Checkins';
use constant access_epd_patch_upload       => 'EPD Upload Patches';
use constant access_epd_release_patches    => 'EPD Release Patches';
use constant access_fusion_dev_manager     => 'Fusion Development Manager';
use constant access_project_manager        => 'Project Manager';
use constant access_patch_classify         => 'Patch Classification';

use constant access_release_manager       => 'Release Manager';
use constant access_dev_manager            => 'Development Manager';
use constant access_developer              => 'Developer';
use constant access_upload_developer       => 'Upload Developer';
use constant access_plat_admin             => 'Platform Admin';
use constant access_nls_upl_dev            => 'NLS Upload Developer';
use constant access_winnt_plat_admin       => 'Apps MS_WIN_NT Platform Admin';
use constant access_upload_manager         => 'Upload Manager';
use constant priv_release_manager        => 10007;
use constant priv_upload_developer       => 10008;
use constant priv_developer              => 10002;
use constant priv_download_any_media     => 9;
use constant priv_epd_upload_developer   => 10127;
use constant priv_epd_upload_rls_manager => 10126;
use constant priv_download_internal_for_qa => 12;
use constant priv_entitlements_update           => 27;
use constant priv_patch_attributes_override     => 24;
use constant priv_manage_license                => 60;

   #
   # Status Groups
   #
use constant email_notification            => 1505;
use constant group_patch_statuses          => 1506;
use constant group_checkin_statuses        => 1507;
use constant group_fixed_bug_statuses      => 1527;
use constant group_patch_types             => 1510;
use constant apf_manager_alert             => 1512;
use constant apf_worker_alert              => 1513;
use constant aru_priority_alert            => 1515;

use constant bugfix_relation_type          => 1541;
use constant bugfix_dependency_access      => 1546;
use constant software_patch_type           => 1547;
use constant documentation_patch_type      => 1548;
use constant nls_patch_type                => 1549;
use constant checkin_dist_type             => 1550;
use constant nls_doc_patch_type            => 1565;

use constant aru_patch_class_in_progress   => 1566;
use constant aru_patch_class_released      => 1567;
use constant aru_patch_class_obsolete      => 1568;
use constant aru_patch_class_all_released  => 1569;
use constant aru_patch_class_restriction   => 1580;

use constant notification_statuses         => 1560;
use constant checkin_events                => 1561;
use constant patch_build_events            => 1562;
use constant patchset_events               => 1563;
use constant upload_events                 => 1564;

use constant group_upload_statuses         => 1583;
use constant group_recommend_statuses      => 1585;

   #
   # Patch recommendation constants
   #
use constant patch_recommend_internal      => 'internal';
use constant patch_recommend_external      => 'external';
use constant patch_recommend_certification => 'certification';
use constant patch_recommend_components    => 'components';

use constant access_patch_recommend_admin => 'PATCH_RECOMMENDATION_ADMIN';

use constant patch_reco_consumer_public   => 'A';
use constant patch_reco_consumer_private  => 'P';


   #
   # Recommended Release constants
   #
use constant access_reco_release_admin => 'RECOMMENDED_RELEASE_ADMIN';


   #
   # Notification statuses.
   #
use constant notify_platform_migration     => 1570;
use constant notify_patch_uploaded         => 1210;
use constant notify_patch_deleted          => 1211;
use constant notify_patch_readme_update    => 1212;
use constant notify_pset_incl_request      => 1220;
use constant notify_trans_sync             => 1571;

   #
   # Notification statuses for Master Upload.
   #
use constant notify_master_uploaded        => 60053;
use constant notify_master_upd_replace     => 60054;
use constant notify_master_approved        => 60055;
use constant notify_master_upd_metadata    => 60057;
use constant notify_master_released        => 60058;

   #
   # Priority statuses
   #
use constant normal_priority               => 115;
use constant escalated_cust_priority       => 116;
use constant escalated_int_priority        => 130;
use constant maint_pack_priority           => 140;
use constant hipo_checkin_priority         => 150;
use constant full_w_merged_priority        => 160;

   #
   # Patch Classification
   #
use constant class_open                    => 170;
use constant class_closed                  => 171;
use constant class_internal                => 172;
use constant class_controlled              => 173;
use constant class_general                 => 174;
use constant class_recommended             => 175;
use constant class_critical                => 176;
use constant class_legislative             => 183;

use constant class_superseded              => 178;
use constant class_defective               => 179;
use constant class_retired                 => 180;
use constant class_not_specified           => 181;

use constant class_private                 => 182;

use constant class_placeholder             => 184;

use constant class_security                => 185;

   #
   # Upload Statuses
   #
use constant upload_requested              => 830;
use constant upload_queued                 => 835;
use constant uploading_patch               => 840;
use constant upload_attempt                => 845;
use constant upload_failure                => 847;
use constant upload_delete_request         => 850;
use constant metadata_update               => 120;

   #
   # Upload Directory Name
   #
use constant upload_dir                => 'aru_upload_dir';

   #
   # Sun specific upload constants
   #
use constant getupdates1_host_id            => 1;
use constant sunsolve_host_id               => 2;
use constant sun_patch_location_id          => 1;
use constant sun_cluster_location_id        => 2;
use constant sun_patch_readme_location_id   => 3;
use constant sun_cluster_readme_location_id => 4;
use constant metadata_release_type          => 'W';
use constant release_type_l                 => 'l';
use constant patch_source                   => 13;
use constant patch_source_internal          => 14;
use constant patch_source_external          => 15;
use constant tag                            => 3;
use constant yes                            => 551;
use constant no                             => 552;
use constant entitlement_firmware           => 'FMW';
use constant entitlement_extended           => 'EXS';
use constant entitlement_software           => 'SW';
   #
   # Rename Statuses
   #

use constant rename_requested              => 20009;
use constant rename_queued                 => 20010;
use constant renaming_patch                => 20011;
use constant rename_attempt                => 20012;

   #
   # Languages
   #
use constant language_US                   => 0;

use constant metalink_user_prefix          => 'ML-';
use constant epd_user_prefix               => 'EPD-';
use constant orion_user_prefix             => 'O-';
use constant smpatch_user_prefix           => 'SC-';
use constant portal_type_orion             => 'Orion';
use constant portal_type_metalink          => 'ARULink';
use constant portal_type_cookie            => 'ARULINKPORTAL';

   #
   # Responsibilities
   #
use constant nls_release_manager           => 5831;
use constant no_responsibility             => 220;
use constant product_line_responsibility   => 4;
use constant aru_developer_responsibility  => 260;
use constant aru_administrator             => 2;
use constant approve_inclusion_request     => 10065;
use constant download_any_media_pack       => 19671;
use constant download_production_patches   => 241;

   #
   # Applications
   #
use constant applications_fusion           => 16001110010050;
use constant applications_fusion_rel_max   => 160011999999999;
use constant applications_fusion_rel_exp   => 1600111;
use constant applications_fusion_rel_name  => '11.1.1.5.0';
use constant applications_fusion_util_ver  => '11.0.0';
use constant applications_fmw12c           => 6000000000;
use constant applications_R12              => 1500;
use constant applications_R12_3             => 1510;
use constant applications_11i              => 1400;
use constant applications_dev_11i          => 1300;
use constant applications_dev_11iX         => 1492;
use constant applications_11i_rel_name     => '11i';
use constant applications_dev11i_rel_name  => 'dev11i';
use constant applications_R12_rel_name     => 'R12';
use constant applications_R123_rel_name   => 'R12.3';
use constant applications_default_release  => 1400;
use constant applications_11_0_0           => 1260;
use constant applications_10_7_0           => 1243;
use constant applications_10_7_NCA         => 1250;
use constant applications_P16_1SC          => 999;
use constant applications_11106            => 80111060;
use constant fusion_group_id               => 14567;
use constant fusion_rel_prefix             => '1600';

   #
   # Source Control Identifiers
   #
use constant arcs_source_control           => 'A';

   #
   # Upload Release cutoff
   #
use constant upload_release_start          => 2000;

   #
   # Filetypes
   #
use constant filetype_jrad                 => 1005;
use constant filetype_executable           => 1006;
use constant filetype_xlf                  => 1025;
use constant filetype_gif                  => 112;
use constant filetype_html                 => 186;
use constant filetype_htm                  => 185;
use constant filetype_txt                  => 217;
use constant filetype_iso                  => 125;
use constant filetype_tar                  => 1625;
use constant filetype_gz                   => 1667;
use constant filetype_tar_gz               => 1848;
use constant filetype_tar_Z                => 1849;
use constant filetype_rpm                  => 1828;
use constant filetype_dmg                  => 1829;
use constant filetype_zip                  => 146;
use constant filetype_class                => 147;
use constant filetype_jar                  => 148;
use constant filetype_pattern              => 151;
use constant filetype_exe                  => 175;
use constant filetype_noship_mk            => 196;
use constant filetype_Z                    => 1066;
use constant filetype_pld                  => 137;
use constant filetype_pll                  => 128;
use constant filetype_ildt                 => 1140;
use constant filetype_xmlp                 => 1150;
use constant filetype_xmlp_xlf             => 1155;
use constant filetype_msi                  => 1156;
use constant filetype_oui                  => 1425;
use constant filetype_lar                  => 1768;

use constant filetype_tar_bz2              => 1850;
use constant filetype_opar                 => 1851;
use constant filetype_ova                  => 1852;
use constant filetype_apk                  => 1853;
use constant filetype_deb                  => 1854;
use constant filetype_uar                  => 1855;
use constant filetype_nupkg                => 1856;
use constant filetype_bin                  => 1857;
use constant filetype_tgz                  => 1858;
use constant filetype_cpio                 => 1859;
use constant filetype_cpio_gz              => 1860;
use constant filetype_pdf                  => 141;
   #
   # Filetype extensions
   #
use constant file_ext_ildt                 => 'ildt';
use constant file_ext_xlf                  => 'xlf';

   #
   # Bug 6808254, default Filetype Name
   #
use constant file_name_default_generic      => 'Default Generic FileType';
use constant filetype_name_stmk             => 'st_mk';
use constant filetype_name_stlib            => 'st_a';
use constant filetype_name_stexe            => 'st_exe';
use constant filetype_name_st_c             => 'st_c';
use constant filetype_name_st_h             => 'st_h';
use constant filetype_name_st_lc            => 'st_lc';
use constant filetype_name_st_pc            => 'st_pc';
use constant filetype_name_st_o             => 'st_o';
use constant filetype_name_st_so            => 'st_so';
use constant filetype_name_st_sl            => 'st_sl';
use constant filetype_name_st_oui           => 'st_oui';
use constant filetype_name_st_sql           => 'st_sql';
use constant filetype_name_st_plb           => 'st_plb';
use constant filetype_name_st_pls           => 'st_pls';
use constant filetype_name_st_pkb           => 'st_pkb';
use constant filetype_name_st_pkh           => 'st_pkh';
use constant filetype_name_st_archives      => 'st_archives';
use constant filetype_name_st_class         => 'st_class';
use constant filetype_name_st_bsq           => 'st_bsq';
use constant filetype_name_st_mk            => 'st_mk';
use constant filetype_name_st_cpp           => 'st_cpp';
use constant filetype_name_st_dat           => 'st_dat';
use constant filetype_name_st_txt           => 'st_txt';
use constant filetype_name_st_jsp           => 'st_jsp';
use constant filetype_name_st_jsfx          => 'st_jsfx';
use constant filetype_name_st_jspf          => 'st_jspf';
use constant filetype_name_st_jsff          => 'st_jsff';
use constant filetype_name_st_uix           => 'st_uix';
use constant filetype_name_st_par           => 'st_par';
use constant filetype_name_st_sh            => 'st_sh';
use constant filetype_name_st_pl            => 'st_pl';
use constant filetype_name_st_pm            => 'st_pm';
use constant filetype_name_st_xml           => 'st_xml';
use constant filetype_name_st_dll           => 'st_dll';
use constant filetype_name_st_pll           => 'st_pll';
use constant filetype_name_st_zip           => 'st_zip';

use constant filetype_id_st_a         => 1405;
use constant filetype_id_st_so        => 1406;
use constant filetype_id_st_o         => 1407;
use constant filetype_id_st_mk        => 1408;
use constant filetype_id_st_exe       => 1409;
use constant filetype_id_st_generic   => 1410;
use constant filetype_id_st_c         => 1411;
use constant filetype_id_st_cpp       => 1412;
use constant filetype_id_st_oui       => 1425;
use constant filetype_id_st_java      => 1485;
use constant filetype_id_st_archives  => 1486;
use constant filetype_id_mar          => 1490;
use constant filetype_id_st_sql       => 1545;
use constant filetype_id_st_plb       => 1546;
use constant filetype_id_st_pls       => 1547;
use constant filetype_id_st_pkh       => 1548;
use constant filetype_id_st_pkb       => 1549;
use constant filetype_id_st_h         => 1550;
use constant filetype_id_st_zip       => 1551;
use constant filetype_id_st_sl        => 1552;
use constant filetype_id_st_class     => 1553;
use constant filetype_id_st_pc        => 1554;
use constant filetype_id_st_lc        => 1555;
use constant filetype_id_st_bsq       => 1565;
use constant filetype_id_st_inc       => 1605;
use constant filetype_id_adf_xlf      => 1626;
use constant filetype_id_st_dat       => 1646;
use constant filetype_id_st_txt       => 1647;
use constant filetype_id_st_jsp       => 1648;
use constant filetype_id_st_jspf      => 1649;
use constant filetype_id_st_jsff      => 1650;
use constant filetype_id_st_jsfx      => 1651;
use constant filetype_id_st_uix       => 1652;
use constant filetype_id_st_par       => 1653;
use constant filetype_id_st_sh        => 1654;
use constant filetype_id_st_pl        => 1655;
use constant filetype_id_st_pm        => 1656;
use constant filetype_id_st_xml       => 1657;

   #
   # Bug 7609600, Support for PLB and SQL filetypes
   #

use constant filetype_name_st_generic       => 'ST Generic Filetype';

   #
   # Dependency types in aru_label_dependencies table
   #
use constant dependency_base                => 'BASE';
use constant dependency_bmin                => 'BMIN';
use constant dependency_bplus               => 'BPLUS';
use constant dependency_hybrid              => 'HYBRID';
use constant dependency_oui                 => 'OUI';
use constant dependency_saoui               => 'SAOUI';
use constant dependency_sa                  => 'SA';
use constant dependency_ocom                => 'OCOM';

   #
   # Standard file names.
   #
use constant file_name_adpatch             => 'ad_apply_patch.xml';

   #
   # MSI related constants
   #
use constant manual_steps_dir              => 'patch/115/manualsteps';
use constant msi_available                 => 'A';
use constant msi_excluded                  => 'E';
use constant msi_overridden                => 'O';

   #
   # General Statistic Codes
   #
use constant graph_statistics              => 1;

   #
   # GSCC code review messages
   #
use constant gscc_request_code_review   =>
   'has been submitted for code review';
use constant gscc_approve_code_review   =>
   'has been approved by Standard owner';
use constant gscc_reject_code_review    =>
   'has been rejected by Standard owner';

   #
   # statistic code prefixes
   #
use constant complete_platform_prefix  => 'Complete Backlog by Platform';
use constant complete_language_prefix  => 'Complete Backlog by Language';
use constant complete_host_prefix      => 'Complete Backlog by Host';
use constant manager_platform_prefix   => 'APF Manager Backlog by Platform';
use constant manager_host_prefix       => 'APF Manager Backlog by Host';
use constant worker_platform_prefix    => 'APF Worker Backlog by Platform';
use constant worker_host_prefix        => 'APF Worker Backlog by Host';
use constant wptg_language_prefix      => 'WPTG Backlog by Language';
use constant wptg_host_prefix          => 'WPTG Backlog by Host';
use constant failure_platform_prefix   => 'ARU Failure Backlog by Platform';
use constant failure_language_prefix   => 'ARU Failure Backlog by Language';
use constant failure_host_prefix       => 'ARU Failure Backlog by Host';
use constant requested_platform_prefix => 'Requested Backlog by Platform';
use constant requested_language_prefix => 'Requested Backlog by Language';
use constant requested_host_prefix     => 'Requested Backlog by Host';


   #
   # Backlog statistic codes
   #
use constant statistic_total_complete       => 10;
use constant statistic_complete_platform    => 11;
use constant statistic_complete_language    => 12;
use constant statistic_complete_host        => 13;
use constant statistic_total_apf_manager    => 14;
use constant statistic_apf_manager_platform => 15;
use constant statistic_apf_manager_host     => 16;
use constant statistic_total_apf_worker     => 17;
use constant statistic_apf_worker_platform  => 18;
use constant statistic_apf_worker_host      => 19;
use constant statistic_total_wptg           => 20;
use constant statistic_wptg_language        => 21;
use constant statistic_wptg_host            => 22;
use constant statistic_total_aru_failure    => 23;
use constant statistic_aru_failure_platform => 24;
use constant statistic_aru_failure_language => 25;
use constant statistic_aru_failure_host     => 26;

   #
   # Backlog status codes
   #
use constant status_complete_backlog       => 1502;
use constant status_apf_manager_backlog    => 1521;
use constant status_apf_worker_backlog     => 1517;
use constant status_wptg_backlog           => 1519;
use constant status_aru_failure_backlog    => 1520;
use constant status_requested_backlog      => 1522;

   #
   # Help for GSCC
   #
use constant gscc_help_id                  => 9;

   #
   # ARU Applications.
   #
use constant application_aruforms          => 1;
use constant application_arucheckin        => 3;
use constant application_apf               => 8;
use constant application_arulink           => 10;
use constant application_aruconnect        => 11;
use constant application_upload            => 12;
use constant application_aruftpd_external  => 13;
use constant application_aruftpd_internal  => 16;
use constant application_nlsftpd           => 14;
use constant application_epd               => 15;
use constant application_aru               => 17;
use constant application_gscc              => 18;
use constant application_otn               => 20;
use constant application_otn_osdc          => 9;

   #
   # PLS Applications
   #
use constant application_pl_suite          => 77;
use constant application_patch_reco        => 224;
use constant application_techstack         => 225;
use constant application_security_comp     => 226;
use constant application_PRA               => 227;
use constant application_checklist         => 228;
use constant application_export_comp       => 229;
use constant application_software_dist     => 230;
use constant application_cert_admin        => 231;
use constant application_3rd_party         => 232;
use constant application_media_upld        => 233;
use constant application_prg_admin         => 234;
use constant application_dlp               => 235;
use constant application_fileset           => 236;
use constant application_license_admin     => 237;
use constant application_dlpt              => 238;

   #
   # User actions.
   #
use constant user_created                  => 990;

   #
   # Constants for EPD.
   #
use constant epd_export_enabled            => 'Y';
use constant epd_export_disabled           => 'N';
use constant epd_export_invalid_country    => 'X';

   #
   # Status IDs for DLPT and License Admin Data Model
   #

use constant dlp_template_id                            => 7500;
use constant dlp_template_type_commercial               => 7501;
use constant dlp_template_type_oneclick                 => 7502;
use constant dlp_template_type_selfstudy                => 7503;
use constant dlp_template_type_document                 => 7504;
use constant dlp_template_type_other                    => 7505;
use constant dlp_template_type_int_restrict             => 7506;
use constant dlp_template_type_linux_vm                 => 7513;
use constant dlp_template_status_draft                  => 7507;
use constant dlp_template_status_active                 => 7508;
use constant dlp_template_status_superseded             => 7509;
use constant dlp_template_status_obsolete               => 7510;
use constant dlp_template_status_expired                => 7514;

use constant alternate_name_type_alias                  => 7511;
use constant alternate_name_type_tag                    => 7512;

   #
   # Status IDs for File Upload Data Model
   #

use constant fileset_id                                 => 7520;
use constant fileset_upload_in_progress                 => 7521;
use constant fileset_upload_error                       => 7522;
use constant fileset_upload_complete                    => 7523;
use constant fileset_upload_tested                      => 7524;
use constant fileset_approved_for_release               => 7525;
use constant fileset_expired                            => 7526;
use constant fileset_ncp_obsolete                       => 7527;
use constant fileset_superseded                         => 7528;
use constant fileset_deprecated                         => 7529;
use constant fileset_upload_type                        => 96501;
use constant fileset_local_upload_type                  => 96502;
   #
   #  Status IDs for Source Code Deposits
   #

use constant source_code_status                         => 7550;
use constant source_code_verified                       => 7551;
use constant source_code_not_confirmed                  => 7552;
use constant source_code_not_received                   => 7553;
use constant source_code_not_exists                     => 7554;

   #
   # Status IDs for Fileset to Multiple Releases
   #

use constant fileset_release_map                        => 7560;
use constant fileset_release_queued                     => 7561;
use constant fileset_release_approved                   => 7562;
use constant fileset_release_rejected                   => 7563;

   #
   # Fileset Migration Constants
   # 

use constant fileset_migr_ocom_source_path      => '/content/pub/www/';
   #
   # ARULink Constants
   #
use constant support_type_extended         => 'E';
use constant support_type_general          => 'G';
use constant support_type_tier_one         => 'T';

   #
   # Constants to log errors by EPD-GSI interface.
   #
use constant epd_invalid_release_create    => 855;
use constant epd_invalid_release_update    => 856;
use constant epd_invalid_data_config       => 857;
use constant epd_invalid_metadata          => 858;

use constant epd_generic_release           => 90000000; # (release_generic)
use constant epd_generic_platform          => 2000; # (platform_generic)
use constant epd_generic_product           => 12000; # (product_epd)

use constant epd_export_screen_denied      => 997;
use constant epd_export_screen_denied_held => 1003;
use constant epd_export_screen_passed      => 998;
use constant epd_admin_override            => 999;
use constant epd_admin_requested_rescreen  => 1000;
use constant epd_export_screen_error       => 1001;
use constant epd_export_screen_bypassed    => 1002;

   #
   # Repository location for EPD files.
   #
use constant epd_repository_location      => 109;

   #
   # For generating new part numbers.
   #
use constant emd_new_part_number_prefix   => 'V';
use constant emd_new_part_number_revision => '01';

   #
   # EPD - Component type ids.
   #
use constant media_type_id                => 12;

   #
   # Used by the EMD utility.
   #
use constant emd_instruction              => 20026;
use constant emd_create_from_zip          => 20027;
use constant emd_create_from_iso          => 20045;
use constant emd_dev_handoff              => 20028;
use constant emd_media_type_zip           => 20034;
use constant emd_media_type_iso           => 20046;
use constant emd_handoff_help             => 20035;
use constant epd_media_type               => 20037;
use constant emd_spreadsheet_upload       => 20040;
use constant emd_spreadsheet_upload_ocom  => 20040;
use constant emd_spreadsheet_upload_sac   => 20041;

use constant emd_developer_privilege       => 49;
use constant emd_release_manager_privilege => 50;

   #
   # File type.
   #
use constant emd_file_type                => 20031;
use constant emd_file_type_multipart      => 20032;
use constant emd_file_type_singlepart     => 20033;

   #
   # For aru_downloads
   #
use constant download_from_repository     => 'R';
use constant download_from_cache          => 'C';
use constant download_complete            => 'C';
use constant download_partial             => 'P';

   #
   # File digest types.
   #
use constant digest_md5                   => 351;
use constant digest_sha1                  => 352;
use constant digest_sha256                => 354;

   #
   #  DB Type
   #
use constant db_type_dev             => 'DEV';
use constant bug_source_default      => 'BUGDB';
use constant bug_source_sun          => 'SUN';

   #
   # For aru_countries
   #
use constant country_US                   => 840;
use constant country_code_US              => 'US';
   #
   # For status codes
   #
use constant by_metalink              => 'By MetaLink';
use constant not_distributed          => 'Not Distributed';

   #
   # For aru_util package
   #
   # Perl date format for ARU is ISO-8601 format. Bug 3645656
   #
use constant perl_date_format        => 'YYYY-MM-DD HH24:MI:SS';
   #
   # See Bug 5370389 for details.
   #
use constant aru_date_format         => 'YYYY/MM/DD HH24:MI:SS';

   #
   #
   # Status code for specifying the application that created
   # the bugfix_id.
   #
use constant aru_application_id      => 825;

   #
   # Security bug abstract.  See bug 14263421.
   # Format for security bug abstract:
   #   "Fix for Bug <bug number>"
   #
use constant security_bug_abstract       => 'Fix for Bug ';
   #
   # Flag to identify whether to show fixed bugs in readme.
   #
use constant fixedbugs_in_readme     => 35310;

   #
   # Constant value for status of backport bugs in Upload
   # Bug 6701182
   #
use constant upload_fixes_bug_valid     => 40038;
use constant upload_fixes_bug_invalid   => 40039;
use constant upload_fixes_bug_default   => 40040;

use constant invalid_bug_bugdb       => 0;
use constant other_error_bug_bugdb   => -1;

   #
   # Bug 6808254, object_type for Generic FileType
   #
use constant obj_type_generic_ft => 'ship';
   #
   #  Bug  6916026
   # backport request statuses
   #
use constant backport_request_new              => 45000;
use constant backport_request_pending          => 45001;
use constant backport_request_bug_filed        => 45002;
use constant backport_request_deleted          => 45003;
use constant backport_request_error            => 45004;
use constant backport_request_withdrawn        => 45005;
use constant backport_request_pendingreview    => 45006;
   #
   # backport legacy request statuses
   #
use constant backport_request_unknown     => 45010;
use constant backport_request_rejected    => 45011;
use constant backport_request_suspended   => 45012;
use constant backport_request_reopened    => 45013;
use constant backport_request_wip         => 45014;
use constant backport_request_accepted    => 45015;
   #
   # backport Request Types
   #
use constant backport_rfi                 => 45050;
use constant backport_blr                 => 45051;
use constant backport_pse                 => 45052;
use constant backport_mlr                 => 45053;
use constant backport_ci                  => 45054;
use constant base_bug                     => 45059;

   #
   # backport help id's
   #
use constant backport_version             => 45070;
use constant backport_platform            => 45071;
use constant backport_support_tracking_ref => 45072;
use constant backport_no_related_blr      => 45073;
use constant backport_error_version       => 45074;
use constant backport_manual_flow         => 45075;

   #
   # backport Responsibility Names
   #
use constant backport_resp_admin          => 'Backport Admin';
use constant backport_resp_tools          => 'Backport Tools';
use constant backport_resp_devmgr         => 'Backport Manager';
use constant backport_resp_user           => 'Backport User';
use constant backport_super_user          => 'Backport Super User';
use constant backport_resp_security       => 'Backport Security';
use constant backport_regress_admin       => 'Backport Regression Admin';
use constant backport_regress_notification =>
   'Backport Regression Notification';
use constant backport_priv_farm_abort => 'APF Farm Abort';
   #
   # misc backport constants
   #
use constant backport_generic_platformid  => 46;
use constant backport_cron_userid         => 1;
use constant backport_help_mailid         => 'BAPTA-HELP_us@oracle.com';
   #
   # backport ade interfacing constants for request framework
   #
use constant backport_request_type       => 45110;
use constant backport_request_module     => 45111;
use constant backport_txn_complete       => 45112;

   #
   # Backport Patch Regression - BUGDB regression constants. Bug 7655492.
   #
use constant backport_regress_rfi         => 'BACKPORT';
use constant backport_regress_blr         => 'BLR';
use constant backport_regress_pse         => 'PATCH';
use constant backport_regress_base_bug    => 'BASEBUG';
use constant backport_regress_mlr         => 'MLR';
use constant backport_regress_cnf         => 'CONFIRMED';

   #  Bug 7596456
   # Aru patch passwords validity days
   #
use constant patch_password_duration_def  => 7;
use constant patch_password_duration_max  => 30;
use constant patch_password_mngr_priv_id  => 53;

   #
   # Bug 13241776
   # EM tags
   #
use constant emomsrolling_tag      => 'EMOMSRolling';

   #
   # tstfwk job constants
   #
use constant tstfwk_job_running      =>
   'Install Test is running in TestFramework';
use constant tstfwk_job_failure         =>
   'Install Test is failure in TestFramework';
use constant tstfwk_job_waiting        =>
   'Install Test is waiting in TestFramework';
use constant tstfwk_test_success       =>
   'Install Test is success in TestFramework';

   #
   # dte job constants
   #
use constant dte_job_completed      => 'COMPLETED';
use constant dte_job_running        => 'RUNNING';
use constant dte_job_failed         => 'FAILED';
use constant dte_job_waiting        => 'WAITING';
use constant dte_job_killed         => 'KILLED';
use constant dte_job_aborted        => 'ABORTED';
use constant dte_test_success       => 'dte_success';
use constant dte_test_failed        => 'dte_failed';

   #
   # bug 8642030 - MLR Metadata status bugfix attribute
   #
use constant mlr_metadata_status     => 20050;
use constant mlr_metadata_incomplete => 1;
use constant mlr_metadata_complete   => 0;

   #
   # Bugfix attribute type for storing extension parent product.
   #
use constant ext_parent_prod_id      => 20055;

   # bug 9351298 - OPack template constants
   #
use constant opack_fusion_productfamily => '"fusionapps"';
use constant opack_fusion_oneoff        => '"singleton"';
use constant opack_fusion_snowball      => '"snowball"';

   #
   # bug 9788042 - ARU Transaction Attributes
   #
use constant trans_attrib_bug_num        => 'BUG_NUM';
use constant trans_attrib_label_branch   => 'LABEL_BRANCH';
use constant trans_attrib_merge_time     => 'TRANS_MERGE_TIME';
use constant trans_attrib_trans_name     => 'TRANSACTION';
use constant trans_attrib_no_aru_patch   => 'NO_ARU_PATCH';
use constant trans_exclude_from_snowball => 'EXCLUDE_FROM_SNOWBALL';
use constant trans_attrib_backport_bug_num => 'BACKPORT_BUG_NUM';
use constant trans_attrib_techstack_prereq => 'TECHSTACK_PREREQ_BUGFIX_LIST';
use constant trans_attrib_removed_files  => 'REMOVED_FILES';
use constant trans_attrib_patchset_ver   => 'PATCHSET_VER';
use constant trans_attrib_allow_skip_patch => 'FUSION_ALLOW_SKIP_PATCH';
use constant trans_attrib_skip_checked_txns => 'SKIP_VALIDATED_TXN_LIST';
use constant trans_attrib_skip_future_txn => 'SKIP_REASON_FUTURE_TXN';
use constant trans_attrib_reset_snowball => 'RESET_SNOWBALL';
use constant trans_attrib_basetxn_seeded => 'BASETXN_DOS_SEEDED';
use constant trans_attrib_frc_cold_patch => 'FORCE_COLD_PATCHING';
use constant trans_attrib_appears_label => 'APPEARS_IN_LABEL';

   #
   # bug 18247894 - ARU Fusion HotPatch attributes
   #
use constant hotpatch_patching_mode    =>
   'PATCHING_MODE_DIRECTLY_MODIFIED_ARTIFACTS';
use constant hotpatch_mw_patching_mode =>
   'PATCHING_MODE_DIRECTLY_MODIFIED_MW_ARTIFACTS';
use constant hotpatch_db_patching_mode =>
   'PATCHING_MODE_DIRECTLY_MODIFIED_DB_ARTIFACTS';
use constant fa_hp_enabled_extns => 'FA_HP_EXTNS';

   #
   # bug 12693235 - ARU Fusion constants
   #
use constant fusion_exclude_from_snowball => 90000;
use constant fusion_view_name             => 90003;

use constant fusion_obsolete_rebuild_cause => 90001;
use constant fusion_obsolete_rebuild_effect => 90002;
use constant fusion_non_snapshot_label      => 90004;
use constant fusion_skipval_superset_patch  => 90005;

use constant fusion_force_rebuild      => 90006;
use constant fusion_skipval_view_name  => 90007;

use constant fusion_hotpatch_mode      => 90008;
use constant fusion_hotpatch_mode_org  => 90015;
use constant fusion_hotpatch_mw_mode   => 90009;
use constant fusion_hotpatch_db_mode   => 90010;
use constant fusion_hotpatch_overall_mode => 90017;
use constant fusion_nls_bugfix_patch => 90018;
use constant fusion_disable_fre_log_gather => 90150;

use constant fusion_coreq_txt => 90011;

   #
   # NLS Hot patch attr
   #
use constant fusion_hotpatch_mode_nls      => 90012;
use constant fusion_hotpatch_mode_nls_org  => 90016;
use constant fusion_hotpatch_mw_mode_nls   => 90013;
use constant fusion_hotpatch_db_mode_nls   => 90014;

use constant fa_snowball_api_bulk_fetch => 100;

   #
   # HOT Patch comparison constants
   #
use constant fa_hp_cmp_no_rel_bundle     => 90020;
use constant fa_hp_cmp_bundle_inc_patch  => 90021;
use constant fa_hp_cmp_bug_bundle_same   => 90022;
use constant fa_hp_cmp_inc_incld_bundle  => 90023;
use constant fa_hp_cmp_result_hot        => 90024;
use constant fa_hp_cmp_result_cold       => 90025;
use constant fa_hp_cmp_cum_result        => 90026;


   #
   # NLS Patching Constants
   #
use constant fa_nls_gp_flag              => 90030;

   #
   # Patch Tags constants
   #
use constant patch_tag_external           => 'E';


   #
   # -Stream Release constants
   #
use constant stream_rel_attr_type   => 90065;

   #
   # Constants defined for identifying minimum opatch version
   #
use constant min_opatch_ver_tag  => 'minimum_opatch_version';

use constant patch_type_psu      => 'PSU';
use constant patch_type_bp       => 'BP';
use constant patch_type_spu      => 'SPU';
use constant patch_type_exadbbp  => 'EXADBBP';
use constant patch_type_ru       => 'RU';

use constant sub_type            => 90071;
   #
   # CPM Proative PSE constants
   #
use constant proactive_pse_rules          => 5100;
use constant proactive_pse_status         => 5110;

use constant proactive_pse_contact   => 'CPUCHAKA';
use constant proactive_pse_customer  => 'PROACTIVE';
use constant internal_pse_customer   => 'INTERNAL';
use constant ems_template_status          => 5112;

use constant throttle_install_type   => 'INSTALL';
use constant throttle_general_type   => 'GENERAL';
use constant throttle_build_type     => 'BUILD';
use constant throttle_backport_type  => 'BACKPORT';
use constant throttle_manager_type   => 'MANAGER';
use constant throttle_worker_type   => 'WORKER';
use constant throttle_bundle_type    => 'BUNDLE';

   #
   # - CPM release types
   #
use constant release_type_mlr => 'MLR';

   #
   # CPM Create Patch constants
   #
use constant create_patch_platforms  => 5130;
   #
   # Series attribute levels
   #
use constant acpsa_level_requests => 1;
use constant acpsa_level_releases => 2;
use constant acpsa_level_series => 3;


use constant aru_distribution_types => 213;

use constant license_inserted => 2500;
use constant license_updated  => 2501;
use constant license_deleted  => 2502;
use constant license_files    => 2503;

   #
   # System Patch tags from bundle.xml
   #
use constant system_target           => 45451;
use constant system_version          => 45452;
use constant system_product_qpart_id => 45453;
use constant system_product_aru_id   => 45454;
use constant system_release_urm_id   => 45455;
use constant system_release_aru_id   => 45456;


use constant subpatch_target           => 45551;
use constant subpatch_version          => 45552;
use constant subpatch_product_qpart_id => 45553;
use constant subpatch_product_aru_id   => 45554;
use constant subpatch_release_urm_id   => 45555;
use constant subpatch_release_aru_id   => 45556;
use constant subpatch_patch_type       => 45557;
use constant subpatch_patching_tool    => 45558;
use constant subpatch_location         => 45559;
use constant subpatch_platform         => 45560;
use constant subpatch_patch_id         => 45561;
use constant subpatch_unique_patch_id  => 45562;

   #
   # SQL automation related constansts
   #

use constant all_upg_dwng_files => 50001;
use constant no_sql_ship        => 50002;

  #
  # EM plugin details
  #

use constant em_plugin_details => 60001;
use constant em_plugin_metadata => 90300;

   #
   # Orphan Product Family
   #
use constant orphan_products   => 'Orphan Products';

   #
   # Product Classification
   #
use constant inactive_classification => 'A';

   #
   # For P4FA
   #
use constant p4fa_base_platform   => 226;
use constant apf_unsup_files => 80082;

   #
   # For URL Splitter
   #
use constant split_url => '!!';

   #
   # License and media status values
   #
use constant license_status                   => 7000;
use constant license_status_active            => 7001;
use constant license_status_retired           => 7002;
use constant license_status_withdrawn         => 7003;
use constant license_status_support_only      => 7004;

use constant clickthru_type_standard          => 7101;
use constant clickthru_type_restricted        => 7102;

use constant media_status                     => 8000;
use constant media_status_in_progress         => 8001;
use constant media_status_upload_tested       => 8002;
use constant media_status_approved            => 8003;
use constant media_status_expired             => 8004;
use constant media_status_ncp_obsolete        => 8005;

use constant akamai_repository_id             => 9;

   #
   # Relationship to mark unsupported bundle patch for conflict checking.
   #
use constant unsupported_bundle               => 95490;

use constant patch_uptime_option  => 70001;

use constant sql_auto_seeding  => 800011;

   #
   # Download Limit Status Values
   #
use constant download_limit_active            => 9001;
use constant download_limit_obsoleted         => 9002;

use constant patch_superseded                 => 1;

  #
  # OSDC download click types
  #
use constant search_by_license_download        => 95760;
use constant search_by_release_download        => 95761;
use constant obsoleted_media_downloads         => 95762;
use constant search_by_dlp_download            => 95764;
use constant india_download                    => 95765;

  #
  # DLP states
  #
use constant dlp_status_group                  => 11200;
use constant dlp_state_draft                   => 11210;
use constant dlp_state_submitted               => 11220;
use constant dlp_state_rejected                => 11230;
use constant dlp_state_approved                => 11240;
use constant dlp_state_active                  => 11250;
use constant dlp_state_recalled                => 11260;
use constant dlp_state_req_obsolete            => 11270;
use constant dlp_state_obsolete                => 11280;

  #
  # OTN audit log specific
  #
use constant otn_dummy_host                    => 'otn host';
use constant otn_dummy_account                 => 'otn';
use constant otn_dummy_path                    => '/otn';

  #
  # OSDC3 golive flags
  #
use constant osdc3_primary_flag          => 'osdc3_primary_yn';
use constant osdc3_secondary_flag        => 'osdc3_secondary_yn';

  #
  # OSDC Download Status Codes
  #
use constant osdc_download_initiated                => 96001;
use constant osdc_download_partial                  => 96002;
use constant osdc_download_completed                => 96003;

  #
  # Status code for purged file(s) from Akamai CDN
  #
use constant purged_from_CDN    => 96080;

  #
  # OTN States
  #
use constant otn_request_submitted               => 96401;
use constant otn_request_approved                => 96402;
use constant otn_request_rejected                => 96403;
use constant otn_request_obsolete                => 96404;
use constant otn_dlp_obsolete                    => 96405;
use constant otn_dlp_recalled                    => 96406;

use constant obs_media_desup_token               => 'cis3FC2kds';
use constant obsmedia_desuptoken_days_valid      => 7;

use constant customized_patch_level              => 96419;

use constant baseline_chkin                      => 96085;




use constant   spb_binary_patches_aru           => 96507;
use constant	spb_binary_patches_location      => 96508;
use constant	spb_tool_patches_aru             => 96509; 
use constant	spb_tool_patches_location        => 96510;
use constant	spb_config_patches_aru           => 96511;
use constant	spb_config_patches_location      => 96512;

use constant spb_series_attrs =>(
               "SPB_BINARY_PATCHES_ARU"         => 96507,
               "SPB_TOOL_PATCHES_ARU"           => 96509,
               "SPB_BINARY_PATCHES_LOCATION"    => 96508,
               "SPB_TOOL_PATCHES_LOCATION"      => 96510,
               "SPB_CONFIG_PATCHES_LOCATION"    => 96512,
               "SPB_CONFIG_PATCHES_ARU"         => 96511,
               "SPB_COMPONENT_CPM_SERIES"       => 96513,
               "SPB_OAM_HOME_COMPONENTS"        => 96514,
               "SPB_OIG_HOME_COMPONENTS"        => 96515,
               "SPB_OUD_HOME_COMPONENTS"        => 96516,
               "SPB_OID_HOME_COMPONENTS"        => 96517,
               "SPB_OID_HOME_COMPONENTS"        => 96518,
               "SPB_OTHER_SERIES_ATTRS"         => 96519,
               "SPB_RUN_ATTRS"                  => 96520);



1;

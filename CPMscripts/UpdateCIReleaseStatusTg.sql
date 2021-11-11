-- Update the list of CI requests to valid to release & 
-- status along with that update tracking group infor of backportbug
declare
lt_pf_list aru_array := aru_array();
varc varchar2(1000);
begin
lt_pf_list := aru_util.split('1161530,1232212,1232351,1232362,1232274,1232353,1232356,1232359,1114196,1260310,1260311,1260312,1260313,1260314,1260315,1260316,1260317,1232238',',');
--lt_pf_list := aru_util.split('33272842,33272843,33272835,33272838,33272836,33272837,33272844,33272845,33272846,33272847,33272848,33272841,33272840,33179121,33272854,33272849,33272851,33272853',',');

for i in lt_pf_list.first..lt_pf_list.last
   loop

 aru_cumulative_request.update_request_status

              (

               pn_codeline_request_id   => lt_pf_list(i)

               , pn_user_id             => 1

               , pn_release_id          => 603571

               , pn_request_status      => 34524

               , pv_comments            => 'Content moved as per customer request'

               );
               end loop;

end;
<?php


function postUrl($ch, $url, $post_data, $headers = array())
{
  curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
  curl_setopt($ch, CURLOPT_POST, true);
  curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
  curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

  $post_data['format'] = 'json';
  curl_setopt($ch, CURLOPT_URL, $url);
  curl_setopt($ch, CURLOPT_POSTFIELDS, $post_data);
  $rv = curl_exec($ch);

  return $rv;
}

$host = 'www.photoshelter.com';
$ch = curl_init();

//login
$data['api_key'] = 'TimSchwartz';
$data['email'] = 'timatron@gmail.com';
$data['password'] = 'abc123';
$data['mode'] = 'token';
$rv = postUrl($ch, "https://$host/psapi/v2/mem/authenticate", $data);
print_r($rv);

$token = json_decode($rv)->data->token;

// //query collection
// $data['api_key'] = 'TimSchwartz';
// $headers = array(
// 'X-PS-Auth-Token: ' . $token,
// );
// $rv = postUrl($ch, "https://$host/psapi/v2/mem/collection/query", $data, $headers);

//query collection
$data['api_key'] = 'TimSchwartz';
// $data['name'] = 'f_list = true - permission = everyone';
//$data['collection_id'] = 'C00006vn5QTCERm0';
// $data['f_list'] = 't';
// $data['permission'] = 'everyone';
$data['visibility'] = 'everyone';

$headers = array(
'X-PS-Auth-Token: ' . $token,
);
$rv = postUrl($ch, "https://$host/psapi/v2/mem/collection/C0000i04P4MEopfU/visibility/update", $data, $headers);
print_r(json_decode($rv));





curl_close($ch);


?>
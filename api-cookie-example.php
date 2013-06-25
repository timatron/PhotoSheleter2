<?php

function postUrl($ch, $url, $post_data, $headers = array())
{

  $ckfile = tempnam("/tmp/tim.cf", "CURLCOOKIE");

  echo $ckfile;

  curl_setopt($ch, CURLOPT_COOKIESESSION, TRUE);
  curl_setopt($ch, CURLOPT_COOKIEJAR, $ckfile);
  curl_setopt($ch, CURLOPT_COOKIEFILE, $ckfile);
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
$data['mode'] = 'cookie';
$rv = postUrl($ch, "https://$host/psapi/v2/mem/authenticate", $data);
print_r($rv);
print_r(curl_error($ch));
print_r(curl_getinfo($ch));
print_r(curl_errno($ch));

curl_close($ch);


?>
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$priorRegistration=Get-Content -LiteralPath (Join-Path $root '..\registration.json') -Raw|ConvertFrom-Json
$final=Join-Path $root '金髪アンドロイド-解説用-感情記号9種追加.rigm'
$verification=Get-Content -LiteralPath (Join-Path $root 'verification.json') -Raw|ConvertFrom-Json
$previews=Get-Content -LiteralPath (Join-Path $root 'native-preview-verification.json') -Raw|ConvertFrom-Json
if(!$verification.passed -or $previews.Count -ne 9 -or @($previews|Where-Object {$_.job.state -ne 'succeeded'}).Count){throw 'Native verification is incomplete'}
$baseline=Join-Path $root '..\金髪アンドロイド-解説用.rigm'
$before=(Get-FileHash -LiteralPath $priorRegistration.path -Algorithm SHA256).Hash
if($before -ne (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash){throw 'Registered character changed since the baseline; preserve that change before updating'}
$backup=Join-Path $root '追加前の登録キャラクター.rigm'
Copy-Item -LiteralPath $priorRegistration.path -Destination $backup
Copy-Item -LiteralPath $final -Destination $priorRegistration.path
$after=(Get-FileHash -LiteralPath $priorRegistration.path -Algorithm SHA256).Hash
if($after -ne (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash){throw 'Library copy does not match the verified artifact'}
@{path=$priorRegistration.path;name='金髪アンドロイド・解説用（感情記号9種追加）';artifact=$final;backup=$backup;beforeSha256=$before;afterSha256=$after;nativePreviewsSucceeded=9}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'registration.json') -Encoding utf8

# Read-only contact sheet of the actual app-rendered PNGs.
Add-Type -AssemblyName System.Drawing
$sheet=New-Object System.Drawing.Bitmap 1440,960
$g=[System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::FromArgb(32,37,46))
$g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font=New-Object System.Drawing.Font 'Yu Gothic UI',18,([System.Drawing.FontStyle]::Regular),([System.Drawing.GraphicsUnit]::Pixel)
$brush=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
foreach($p in $previews) {
 $index=$p.kind-1;$x=($index%3)*480;$y=[Math]::Floor($index/3)*320
 $im=[System.Drawing.Image]::FromFile($p.path)
 $g.DrawImage($im,[System.Drawing.Rectangle]::new($x,$y,480,287),0,0,720,430,[System.Drawing.GraphicsUnit]::Pixel)
 $g.DrawString(($p.kind.ToString('00')+'  '+$p.name),$font,$brush,[single]($x+15),[single]($y+291))
 $im.Dispose()
}
$sheet.Save((Join-Path $root 'アプリ表示確認-9種類.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$brush.Dispose();$font.Dispose();$g.Dispose();$sheet.Dispose()

$signs=Get-Content -LiteralPath (Join-Path $root 'symbols.json') -Raw|ConvertFrom-Json
$presets=@($signs|ForEach-Object { @{name=$_.name;variants=@(@{groupId=$_.parentId;partId=$_.id});blinkAnimate=$true;mouthAnimate=$true;rigSafe=$true} })
$presets|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $root '感情記号設定.json') -Encoding utf8
@'
追加した9種類を既存の「感情記号」グループに登録しました。
キャラクター名：金髪アンドロイド・解説用（感情記号9種追加）

追加：！・びっくり、？・疑問、！？・驚きと疑問、！！・強い驚き、
驚き・集中線、衝撃・ギザギザ、動揺・汗しぶき、ガーン・縦線、ひらめき・電球。
元の6記号と「なし」を含め、16項目から切り替えできます。

動画編集の差分グループで「感情記号」を選び、使いたい記号を選択して適用します。
キャラクター編集では、同グループ内の * 付き画像を1つ表示します。
初期状態は「なし」です。頭の動きに追従するように設定しています。

PNGは背景透明、ベクター描画から3倍解像度で作成しています。
「感情記号設定.json」に各記号の実際のグループID・パーツIDを保存しました。
9枚のアプリ表示確認と、旧画像・旧部品・ボーン・メッシュ・パラメータの保持を検証済みです。
追加前の登録キャラクター.rigm は元の登録データの控えです。
テストは非表示のアプリで行い、表示確認後にテスト用プロセスを終了しました。
'@|Set-Content -LiteralPath (Join-Path $root '使い方.txt') -Encoding utf8
Write-Output ('Updated registered character: '+$priorRegistration.path)

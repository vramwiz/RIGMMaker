$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -LiteralPath (Join-Path $PSScriptRoot 'symbols.cs') -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Runtime,System.Runtime.InteropServices,System.Private.Windows.GdiPlus,System.Private.Windows.Core
$items=@(
 @{kind=1;name='！・びっくり';width=240;height=280;x=752;y=130},
 @{kind=2;name='？・疑問';width=250;height=280;x=755;y=130},
 @{kind=3;name='！？・驚きと疑問';width=360;height=280;x=743;y=135},
 @{kind=4;name='！！・強い驚き';width=300;height=280;x=757;y=130},
 @{kind=5;name='驚き・集中線';width=1020;height=640;x=60;y=0},
 @{kind=6;name='衝撃・ギザギザ';width=280;height=280;x=770;y=125},
 @{kind=7;name='動揺・汗しぶき';width=250;height=280;x=752;y=140},
 @{kind=8;name='ガーン・縦線';width=250;height=280;x=160;y=125},
 @{kind=9;name='ひらめき・電球';width=260;height=280;x=770;y=110}
)
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'png') -Force|Out-Null
foreach($item in $items) {
 $item.file='png/symbol-'+$item.kind.ToString('00')+'.png'
 [MangaSigns]::Save((Join-Path $PSScriptRoot $item.file),$item.kind,$item.width,$item.height)
}
$items|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'symbols.json') -Encoding utf8
Write-Output ('Created transparent signs: '+$items.Count)

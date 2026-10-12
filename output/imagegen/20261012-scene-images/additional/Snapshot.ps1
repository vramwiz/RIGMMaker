$ErrorActionPreference='Stop'
$invoke=Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-Live.ps1'
$s=& $invoke -Command app-script-status -OutputFile (Join-Path $PSScriptRoot 'latest-status.json')
$offset=0
$rows=@()
do {
 $a=@{projectId=$s.projectId;revision=$s.revision;offset=$offset;limit=1}|ConvertTo-Json -Compress
 $p=& $invoke -Command app-script-scenes -ArgsJson $a
 $rows+=@($p.rows)
 $offset=$p.nextOffset
}while($p.hasMore)
$all=@{projectId=$s.projectId;revision=$s.revision;title=$s.title;background=$p.background;thumbnail=$p.thumbnail;rows=$rows}
$all|ConvertTo-Json -Depth 60|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'latest-scenes.json') -Encoding UTF8
@{revision=$s.revision;thumbnailSourcesReady=$p.thumbnail.sourcesReady;notApproved=@(@($p.background)+@($rows)|Where-Object {-not $_.imageApproved}|Select-Object id,title);thumbnailState=$p.thumbnail.imageRequest.state}|ConvertTo-Json -Depth 5

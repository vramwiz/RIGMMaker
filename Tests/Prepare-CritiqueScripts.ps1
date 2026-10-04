#requires -Version 7.0
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
if(-not $OutputDirectory){$OutputDirectory=Join-Path (Split-Path -Parent $PSScriptRoot) 'Win64\Validation\CritiqueProduction\Scripts'}
$dataset=@'
[
  {
    "id": "anime",
    "title": "星灯り郵便局｜架空アニメ批評・制作例",
    "fiction": true,
    "voice": {
      "name": "東北きりたん",
      "style": "ノーマル",
      "styleId": 108,
      "engineUrl": "http://127.0.0.1:50021",
      "speed": 0.98
    },
    "chart": {
      "kind": "radar",
      "title": "総評（架空作品・評価例）",
      "maximum": 5,
      "color": "#55B9DD",
      "items": [
        {
          "label": "脚本",
          "value": 4.3
        },
        {
          "label": "人物",
          "value": 4.5
        },
        {
          "label": "演出",
          "value": 4.1
        },
        {
          "label": "テンポ",
          "value": 3.4
        },
        {
          "label": "余韻",
          "value": 4.6
        }
      ]
    },
    "imageNames": [],
    "cues": [
      {
        "id": "cue01",
        "scene": "intro",
        "emotion": "neutral",
        "text": "こんにちは、東北きりたんです。今日は架空のアニメ、星灯り郵便局を題材に、見どころと気になる点を整理します。",
        "subtitle": "架空アニメ「星灯り郵便局」|魅力と気になる点を整理",
        "pause": 0.35
      },
      {
        "id": "cue02",
        "scene": "intro",
        "emotion": "neutral",
        "text": "この作品は実在しません。動画制作のために設定した物語で、総評の数字も説明用の評価例です。最後にチャートでまとめます。",
        "subtitle": "架空作品を使った制作例|点数も説明用の評価例です",
        "pause": 0.35
      },
      {
        "id": "cue03",
        "scene": "intro",
        "emotion": "neutral",
        "text": "舞台は海辺の町にある、小さな夜間郵便局。若い配達人が、宛先の読めない手紙をきっかけに、町に残る記憶をたどります。",
        "subtitle": "海辺の夜間郵便局|読めない宛先から始まる物語",
        "pause": 0.35
      },
      {
        "id": "cue04",
        "scene": "appeal",
        "emotion": "happy",
        "text": "一番の魅力は、手紙が事件の道具ではなく、人の気持ちを運ぶものとして描かれることです。答えを急がず、相手の言葉を待ちます。",
        "subtitle": "手紙が運ぶ、人の気持ち|答えを急がない物語",
        "pause": 0.35
      },
      {
        "id": "cue05",
        "scene": "appeal",
        "emotion": "gentle",
        "text": "たとえば、店の灯りが消えたあとに届く一通。返事を書くかどうかを悩む時間が、主人公と町の人の距離を少しずつ変えていきます。",
        "subtitle": "返事を書くまでの時間|少しずつ変わる人との距離",
        "pause": 0.35
      },
      {
        "id": "cue06",
        "scene": "appeal",
        "emotion": "surprised",
        "text": "この画像の郵便局の窓を見ると、外の青い夜と、室内の暖かな光が対比になっています。言葉にしない安心感を、画面の色で伝える場面です。",
        "subtitle": "青い夜と暖かな窓|色で伝える安心感",
        "pause": 0.35
      },
      {
        "id": "cue07",
        "scene": "appeal",
        "emotion": "joy",
        "text": "人物の魅力も、派手な成長より、小さな選択にあります。分からないときに尋ねる。謝るべきところで謝る。その積み重ねに説得力があります。",
        "subtitle": "人物を支える小さな選択|尋ねる・謝る・待つ",
        "pause": 0.35
      },
      {
        "id": "cue08",
        "scene": "appeal",
        "emotion": "gentle",
        "text": "演出は、声のない時間を大切にする想定です。波の音や紙を折る音が、会話の余白を支えます。静かな作品が好きなら、ここを楽しめそうです。",
        "subtitle": "波や紙の音が支える余白|静かな演出を楽しむ",
        "pause": 0.35
      },
      {
        "id": "cue09",
        "scene": "appeal",
        "emotion": "happy",
        "text": "結末を知ったあとでも見返せる場面を期待します。背景に見えた町の灯りが、後半では誰かの帰りを待つ光に変わる。その再発見が良さそうです。",
        "subtitle": "見返して気づく町の灯り|結末のあとに変わる意味",
        "pause": 0.35
      },
      {
        "id": "cue10",
        "scene": "concerns",
        "emotion": "doubt",
        "text": "気になるのは、序盤のテンポです。静かな雰囲気が続くぶん、配達人の目的が見えないと、視聴者が物語に入るまで時間がかかります。",
        "subtitle": "序盤のテンポに注意|主人公の目的は伝わるか",
        "pause": 0.35
      },
      {
        "id": "cue11",
        "scene": "concerns",
        "emotion": "serious",
        "text": "また、感情の変化を毎回すべて手紙に託すと、展開が似てしまいます。顔を合わせて話す回や、手紙を届けないという選択も、変化として欲しいところです。",
        "subtitle": "手紙だけに頼る展開の弱さ|直接話す回にも期待",
        "pause": 0.35
      },
      {
        "id": "cue12",
        "scene": "concerns",
        "emotion": "confused",
        "text": "落ち着いた演出は魅力ですが、大切な決断まで同じ温度になると、場面の区別がつきません。音や構図に、一段の変化があると良さそうです。",
        "subtitle": "大切な決断が埋もれないか|音と構図の変化に期待",
        "pause": 0.35
      },
      {
        "id": "cue13",
        "scene": "concerns",
        "emotion": "neutral",
        "text": "静かな作風そのものが問題なのではありません。何を待っている時間なのかが、画面から伝わるかどうかを見たい作品です。",
        "subtitle": "静かな時間に意味はあるか|何を待つ場面なのか",
        "pause": 0.35
      },
      {
        "id": "cue14",
        "scene": "verdict",
        "emotion": "neutral",
        "text": "総評をチャートにしました。脚本、人物、演出、テンポ、余韻の五つを、五点満点の架空の評価例で比べています。実在作品の点数ではありません。",
        "subtitle": "総評：五つの軸で比較|架空作品の評価例・五点満点",
        "pause": 0.35
      },
      {
        "id": "cue15",
        "scene": "verdict",
        "emotion": "happy",
        "text": "人物と余韻は高め、テンポはやや控えめです。平均点だけで決めず、静かな会話や、あとから気づく演出を楽しみたいかを考えると、相性を判断しやすくなります。",
        "subtitle": "人物と余韻に魅力|平均点より、自分との相性",
        "pause": 0.35
      },
      {
        "id": "cue16",
        "scene": "verdict",
        "emotion": "gentle",
        "text": "おすすめしたいのは、登場人物の気持ちをゆっくり追う作品が好きな人です。毎話の大きな事件や、速い展開を求めるなら、少し物足りないかもしれません。",
        "subtitle": "気持ちをゆっくり追いたい人へ|速い展開を求める人には注意",
        "pause": 0.35
      },
      {
        "id": "cue17",
        "scene": "verdict",
        "emotion": "serious",
        "text": "これは見方を整理するためのサンプルです。実際の作品を紹介するときは、場面の根拠を示し、好みと評価を分けて話したいですね。",
        "subtitle": "根拠を示し、好みと評価を分ける|実作品の紹介にも使える流れ",
        "pause": 0.35
      },
      {
        "id": "cue18",
        "scene": "verdict",
        "emotion": "joy",
        "text": "今回は、星灯り郵便局の魅力と課題を整理しました。気になる場面を言葉にし、最後に軸を揃えて比べる。この流れで、解説動画を作っていきます。",
        "subtitle": "魅力・課題・総評を揃えて伝える|ご視聴ありがとうございました",
        "pause": 0.35
      }
    ]
  },
  {
    "id": "manga",
    "title": "雨町の地図屋｜架空マンガおすすめ・制作例",
    "fiction": true,
    "voice": {
      "name": "東北きりたん",
      "style": "ノーマル",
      "styleId": 108,
      "engineUrl": "http://127.0.0.1:50021",
      "speed": 0.98
    },
    "chart": {
      "kind": "radar",
      "title": "総評（架空作品・評価例）",
      "maximum": 5,
      "color": "#55B9DD",
      "items": [
        {
          "label": "物語",
          "value": 4
        },
        {
          "label": "人物",
          "value": 4.4
        },
        {
          "label": "コマ割り",
          "value": 4.6
        },
        {
          "label": "読みやすさ",
          "value": 4.1
        },
        {
          "label": "余韻",
          "value": 4.5
        }
      ]
    },
    "imageNames": [
      "01_rainy_mapmaker_shop.png",
      "02_handmade_map_desk.png",
      "03_branching_crossroads.png",
      "04_town_after_rain.png"
    ],
    "cues": [
      {
        "id": "cue01",
        "scene": "intro",
        "emotion": "neutral",
        "text": "こんにちは、東北きりたんです。今回は架空のマンガ、雨町の地図屋をおすすめする動画です。どんな人に合いそうか、魅力と注意点を整理します。",
        "subtitle": "架空マンガ「雨町の地図屋」|魅力と注意点を整理",
        "pause": 0.35
      },
      {
        "id": "cue02",
        "scene": "intro",
        "emotion": "neutral",
        "text": "この作品は実在しません。ここで話す物語や点数は、動画制作のための例です。実在するマンガの紹介や、読者の感想ではありません。",
        "subtitle": "架空作品を使った制作例|点数も説明用の評価例です",
        "pause": 0.35
      },
      {
        "id": "cue03",
        "scene": "intro",
        "emotion": "neutral",
        "text": "舞台は、雨の多い小さな町。若い地図職人が、お客さんの話を聞き、その人に必要な道を一枚の地図に描く、静かな連作という設定です。",
        "subtitle": "雨の多い町の地図職人|必要な道を一枚に描く",
        "pause": 0.35
      },
      {
        "id": "cue04",
        "scene": "appeal",
        "emotion": "happy",
        "text": "魅力は、地図が正しい道順を示すだけではないところです。寄り道したい場所や、まだ通る勇気のない道まで、依頼人の気持ちが線に表れます。",
        "subtitle": "道順だけではない地図|線に表れる依頼人の気持ち",
        "pause": 0.35
      },
      {
        "id": "cue05",
        "scene": "appeal",
        "emotion": "surprised",
        "text": "この画像では、紙と色鉛筆を並べた机を見せています。手で描く地図には、直した跡や余白が残る。それが、人物の迷いを伝える手掛かりになります。",
        "subtitle": "紙と色鉛筆を並べた机|直した跡や余白にも意味がある",
        "pause": 0.35
      },
      {
        "id": "cue06",
        "scene": "appeal",
        "emotion": "gentle",
        "text": "たとえば、久しぶりに誰かを訪ねたいお客さん。目的地への最短距離より、気持ちを整えながら歩ける道を選ぶ。その相談が一話の中心になります。",
        "subtitle": "最短距離より、気持ちを整える道|相談を中心に描く一話",
        "pause": 0.35
      },
      {
        "id": "cue07",
        "scene": "appeal",
        "emotion": "joy",
        "text": "マンガならではの面白さは、コマの流れを道に重ねられることです。曲がり角でページをめくり、細い道では小さなコマを続ける。読む速度も、歩く速度に変わります。",
        "subtitle": "コマの流れを道に重ねる|読む速度が歩く速度に変わる",
        "pause": 0.35
      },
      {
        "id": "cue08",
        "scene": "appeal",
        "emotion": "happy",
        "text": "背景の看板や窓、橋の位置が繰り返し登場すると、読者も町の地理を覚えられます。前に通った場所が別の人の話につながると、町全体に愛着が生まれそうです。",
        "subtitle": "繰り返し描かれる町の風景|別の人の話につながる場所",
        "pause": 0.35
      },
      {
        "id": "cue09",
        "scene": "appeal",
        "emotion": "gentle",
        "text": "会話が穏やかでも、人物の選択には違いがほしいところです。主人公が道を決めるのではなく、依頼人が自分で選ぶ。この距離感が、作品の優しさになりそうです。",
        "subtitle": "道を選ぶのは依頼人自身|押しつけない距離感",
        "pause": 0.35
      },
      {
        "id": "cue10",
        "scene": "concerns",
        "emotion": "sad",
        "text": "気になる点は、相談の結末が毎回きれいにまとまりすぎることです。迷いが一枚の地図ですべて解決すると、人物の悩みが軽く見えてしまうかもしれません。",
        "subtitle": "悩みが簡単に解決しすぎないか|残る迷いも描いてほしい",
        "pause": 0.35
      },
      {
        "id": "cue11",
        "scene": "concerns",
        "emotion": "serious",
        "text": "また、背景の描き込みが多い作品は、読む順番が分かりにくくなることがあります。重要な手や表情は大きく見せ、地図の説明を詰め込みすぎない構成を期待します。",
        "subtitle": "背景の密度と読みやすさ|手や表情が伝わる構成に期待",
        "pause": 0.35
      },
      {
        "id": "cue12",
        "scene": "concerns",
        "emotion": "confused",
        "text": "雨や静かな会話が続くぶん、各話の印象も似やすくなります。晴れた日の依頼や、道を描かずに歩く回があると、連作に良い変化が生まれそうです。",
        "subtitle": "似た印象が続かないか|晴れの日や歩く回にも期待",
        "pause": 0.35
      },
      {
        "id": "cue13",
        "scene": "concerns",
        "emotion": "neutral",
        "text": "大きな事件を期待すると、少しゆっくりした作品に感じるかもしれません。町の細部や、人と人の距離の変化を読むのが好きかどうかが、相性の分かれ目です。",
        "subtitle": "町の細部と距離の変化を読む|ゆっくりした作品との相性",
        "pause": 0.35
      },
      {
        "id": "cue14",
        "scene": "verdict",
        "emotion": "neutral",
        "text": "総評では、物語、人物、コマ割り、読みやすさ、余韻を五点満点で並べました。数字は架空の評価例で、購入のための実作品評価ではありません。",
        "subtitle": "総評：五つの軸で比較|架空作品の評価例・五点満点",
        "pause": 0.35
      },
      {
        "id": "cue15",
        "scene": "verdict",
        "emotion": "happy",
        "text": "コマ割りと余韻を高めに、物語の変化は少し控えめにしています。平均点ではなく、ゆっくり読み返したいか、町の風景を楽しみたいかを判断の軸にしてみてください。",
        "subtitle": "コマ割りと余韻に魅力|自分が楽しみたい軸を選ぶ",
        "pause": 0.35
      },
      {
        "id": "cue16",
        "scene": "verdict",
        "emotion": "gentle",
        "text": "おすすめしたいのは、暮らしの中の小さな選択や、背景から伝わる空気を楽しむ人です。読み終わったあと、自分の町を少し歩いてみたくなる。そんな作品を想定しています。",
        "subtitle": "小さな選択と空気を楽しむ人へ|自分の町も歩きたくなる物語",
        "pause": 0.35
      },
      {
        "id": "cue17",
        "scene": "verdict",
        "emotion": "serious",
        "text": "実際にマンガを紹介するときは、ネタバレの範囲を決め、コマや台詞の根拠を確かめて話したいですね。絵の魅力と、好みの問題を分けることも大切です。",
        "subtitle": "ネタバレの範囲と根拠を確認|絵の魅力と好みを分ける",
        "pause": 0.35
      },
      {
        "id": "cue18",
        "scene": "verdict",
        "emotion": "joy",
        "text": "今回は、雨町の地図屋という架空のマンガを使って、おすすめ動画の形を作りました。魅力、注意点、向いている人を揃えて伝える。ご視聴ありがとうございました。",
        "subtitle": "魅力・注意点・向いている人を伝える|ご視聴ありがとうございました",
        "pause": 0.35
      }
    ]
  }
]
'@ | ConvertFrom-Json
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$results=@()
foreach($work in $dataset){
  foreach($cue in $work.cues){$cue.subtitle=$cue.subtitle.Replace('|',[Environment]::NewLine)}
  $json=Join-Path $OutputDirectory ($work.id+'-script.json')
  $text=Join-Path $OutputDirectory ($work.id+'-narration.txt')
  if((Test-Path -LiteralPath $json) -or (Test-Path -LiteralPath $text)){throw 'Use a fresh output directory; existing production scripts will not be overwritten'}
  [IO.File]::WriteAllText($json,($work | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($true))
  $narration=($work.cues | ForEach-Object {$_.text}) -join [Environment]::NewLine
  [IO.File]::WriteAllText($text,$narration,[Text.UTF8Encoding]::new($true))
  $characters=($work.cues | ForEach-Object {$_.text.Length} | Measure-Object -Sum).Sum
  $results+= [pscustomobject]@{id=$work.id;json=$json;narration=$text;cueCount=$work.cues.Count;characters=$characters;estimatedSeconds=[Math]::Round($characters/6.33/0.98+$work.cues.Count*0.35,2);actualVoiceGeneration=$false}
}
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'preparation.json') -Encoding utf8BOM
$results | ConvertTo-Json -Depth 10


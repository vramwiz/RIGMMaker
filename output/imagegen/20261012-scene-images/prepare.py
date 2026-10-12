import json
from pathlib import Path

root=Path(__file__).parent
snapshot=json.loads((root/'all-scenes.json').read_text(encoding='utf-8-sig'))
common='動画の漫画紹介に使う、横長16:9、1920x1080を目標とした高品質なカラー漫画イラストを1枚。細く明瞭な線、簡潔なセル塗り、自然な柔らかい光、親しみやすい異世界ラブコメの雰囲気。単一の完成した情景で、文字・吹き出し・字幕・ロゴ・透かし・枠・分割コマを入れない。キャラクターは公式参照画像の外見を維持する。ナナ：白銀の長い髪、中央の長い前髪と外へ跳ねる毛束、赤い半目がちな瞳、色白で細身、黒いチョーカー、小さな襟飾りのクリーム色の上衣、ゆったりした黒～濃いチャコール色の上着と金色の袖ボタン。髪の横の跳ねは毛束であり獣耳や角にしない。露出を強調しない普段着。ながれ：短く自然に乱れた黒髪、黒い瞳、色白で普通の体格の日本人青年、素朴で少し戸惑った表情。公式では服装の色を確認できないため本セットでは無地のくすんだ青い長袖上衣・濃い灰色のズボンで統一する。登場時の顔立ち・髪型・服の色・体格を全画像で維持。参照にある印刷文字や漫画コマそのものを複製せず、下記の新しい場面を描く。'
scenes={
1:'作品紹介の導入。ナナが森林の小道の入口でこちらを向き、案内を申し出るように片手を軽く差し出している。背景に木々の間から遠くの異世界の小さな町と丘が見える。人懐こい笑顔に少しだけいたずらっぽさを含む。明るい期待感。人物と場所を見やすく大きく配置。',
2:'異世界というジャンルと少し変わった設定の紹介。広がる異世界の町並み、緑の丘、石橋、遠景の城を背景に、小道に並ぶナナとながれ。ナナは余裕のある笑顔で景色を示し、ながれは驚きながら眺める。台本にない戦闘や具体的な新事件は追加しない。旅の始まりの広い構図。',
3:'ある日突然、青年ながれが異世界の森に転移して困っている場面。木漏れ日の森の小道でながれは周囲を見回し、ナナが数歩先から彼に気付き振り返っている。ながれを画面の中心に、ナナの顔も分かる距離に置く。転移を示す柔らかな光の粒を少しだけ残し、派手な魔法陣や武器は付けない。次の森の案内場面へつながる。',
4:'森でながれを助けたナナが、異世界の作法を教えようと案内している。直前と同じ森の小道・服装・昼の木漏れ日。ナナは一歩先で振り返りながら指を1本立てて説明、ながれは真面目に聞いている。ナナの親切そうな顔にかすかな企みを感じる、軽やかな会話の情景。',
5:'ナナの下心と暮らしへの願望を示す、軽いコメディの場面。同じ森の小道でナナが胸元の前で両手を合わせて期待に満ちた笑顔、ながれは少し後ろで不思議そうに眺める。ナナのそばに文字のない柔らかな小さな想像の雲を一つだけ置き、その中に温かな小さな家・食卓のパンとスープを描く。控えめな生活への憧れとして表現し、金貨の山や豪華な王宮は描かない。',
6:'どこまでが嘘なのかという作品の面白さ。森の出口でナナをやや大きく描き、公式参照に近い半目のいたずらっぽい微笑みで人差し指を口の前に軽く立てる。背後のながれは首を傾げて困惑。直前までと同じ服と顔、穏やかな昼の光。恐怖や悪役的な闇演出にせず、親しみのあるラブコメの秘密めいた表情にする。',
7:'青年から見た異世界はナナの説明頼み。森を出た異世界の小さな村の入口で、ナナが木の道しるべと町並みを指して堂々と説明し、ながれがその説明を信じて頷いている。道しるべには文字を書かず、単純な矢印と家の図形だけ。前の森が遠くに残る、場面の連続した構図。',
8:'異世界の常識とナナの都合のよい説明の境目が分からなくなる場面。同じ村の広場でナナはもっともらしく片手を開いて説明し、ながれは眉を上げて考え込む。後ろには素朴な異世界の屋台、見慣れない形の果物と穏やかな村人を控えめに描く。誰かを騙す具体的事件は作らず、二人の表情の対比で不思議さと軽い可笑しみを示す。',
9:'気楽に楽しむ異世界の旅。村を出た緑の丘の街道をナナとながれが並んで歩き、ナナが少し先を元気に案内、ながれも柔らかい笑顔。遠くにこれまでの町、石橋、青空と雲。二人の白髪と黒髪、服装、顔をはっきり維持。明るく爽やかな広い旅の景色、物語の紹介を締める余韻。',
11:'漫画紹介動画の締めに使う温かい挨拶の情景。これまでの丘の小道に立ったナナとながれがこちらへ穏やかに手を振る。ナナは少し得意げな笑顔、ながれは自然で親しみやすい笑顔。人物の外見と服装を前の場面から維持し、背後に異世界の町と柔らかな夕方の光。文字なしで、すっきり見やすい一枚絵。'
}
plan={'projectId':snapshot['projectId'],'title':snapshot['title'],'mode':'built-in image_gen','assumption':'All ordinary image prompts were blank. Scene illustration prompts were derived from all 44 live source cues under the user instruction to generate and send. Existing summary chart is retained. Optional common background is not added. Thumbnail is deferred until human confirmations permit its request.','canonicalAppearance':common,'sources':['https://comic-walker.com/detail/KC_019962_S'],'references':['official-character-reference.jpg','official-episode-reference.jpg','official-episode2-reference.jpg','official-episode4-reference.jpg'],'rows':[]}
for row in snapshot['rows']:
    n=row['sceneNumber']
    if n in scenes:
        plan['rows'].append({'sceneNumber':n,'sceneId':row['id'],'title':row['title'],'sourceCues':row['sourceCues'],'prompt':common+'\n今回の場面：'+scenes[n],'output':f'scene-{n:02}.png'})
(root/'generation-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'images':len(plan['rows']),'sceneNumbers':[r['sceneNumber'] for r in plan['rows']]},ensure_ascii=False))

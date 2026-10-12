procedure CheckMovieText;
  procedure Contrast(Bitmap: TBitmap; const Area: TRect; const Name: string);
  begin
    var Black := 0; var White := 0;
    for var Y := Area.Top to Area.Bottom-1 do for var X := Area.Left to Area.Right-1 do begin
      var C := ColorToRGB(Bitmap.Canvas.Pixels[X,Y]);
      if (GetRValue(C)<20) and (GetGValue(C)<20) and (GetBValue(C)<20) then Inc(Black);
      if (GetRValue(C)>230) and (GetGValue(C)>230) and (GetBValue(C)>230) then Inc(White);
    end;
    Check((Black>10) and (White>10) and (Black<Area.Width*Area.Height div 2),Name+' contains white glyphs and a black outline');
  end;
  procedure SavePng(Bitmap: TBitmap; const Name: string);
  begin var Png := TPngImage.Create; try Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png')); finally Png.Free; end; end;
  procedure BackdropPixel(Bitmap: TBitmap; X,Y: Integer; Background: TColor; const Name: string);
  begin
    var Actual := ColorToRGB(Bitmap.Canvas.Pixels[X,Y]); var Base := ColorToRGB(Background);
    Check((Abs(Integer(GetRValue(Actual))-Integer(GetRValue(Base))*89 div 255)<=2) and
      (Abs(Integer(GetGValue(Actual))-Integer(GetGValue(Base))*89 div 255)<=2) and
      (Abs(Integer(GetBValue(Actual))-Integer(GetBValue(Base))*89 div 255)<=2),Name+' retains background colour through translucent black');
  end;
begin
  var Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(700,160); Bitmap.Canvas.Font.Name := 'Yu Gothic UI'; Bitmap.Canvas.Font.Height := -44;
    Bitmap.Canvas.Font.Color := clWhite;
    for var Colour in [clWhite,TColor($808080)] do begin
      Bitmap.Canvas.Brush.Color := Colour; Bitmap.Canvas.FillRect(Rect(0,0,700,160));
      Check(DrawMovieText(Bitmap.Canvas,'シーン名 ＆ 日本語の字幕',Rect(8,8,690,150),DT_LEFT or DT_WORDBREAK)>0,
        'shared outlined text renders on background '+IntToHex(Colour,6));
      Contrast(Bitmap,Rect(0,0,700,160),'shared text '+IntToHex(Colour,6));
      SavePng(Bitmap,'outlined-text-'+IntToHex(Colour,6));
    end;
    var Objects := GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS);
    for var I := 1 to 500 do DrawMovieText(Bitmap.Canvas,'連続プレビュー',Rect(8,8,690,150),DT_LEFT);
    Check(GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS)<=Objects+1,'continuous text rendering releases temporary GDI pens');
    Bitmap.Canvas.Font.Height := -36;
    for var Colour in [clWhite,clAqua] do begin
      Bitmap.Canvas.Brush.Color := Colour; Bitmap.Canvas.FillRect(Rect(0,0,700,160));
      Check(DrawMovieLabel(Bitmap.Canvas,'短い章名',Rect(20,20,680,150),DT_LEFT or DT_WORDBREAK)>0,'label renders on '+IntToHex(Colour,6));
      BackdropPixel(Bitmap,18,18,Colour,'label padding '+IntToHex(Colour,6));
      Check((ColorToRGB(Bitmap.Canvas.Pixels[500,40])=ColorToRGB(Colour)) and
        (ColorToRGB(Bitmap.Canvas.Pixels[40,120])=ColorToRGB(Colour)),'short label does not darken unused width or height');
      SavePng(Bitmap,'label-backdrop-'+IntToHex(Colour,6));
    end;
    Bitmap.Canvas.Brush.Color := clWhite; Bitmap.Canvas.FillRect(Rect(0,0,700,160));
    DrawMovieLabel(Bitmap.Canvas,'',Rect(20,20,680,150),DT_LEFT);
    DrawMovieLabel(Bitmap.Canvas,'   ',Rect(20,20,680,150),DT_LEFT);
    Check(ColorToRGB(Bitmap.Canvas.Pixels[20,20])=ColorToRGB(clWhite),'empty and whitespace labels leave no dark panel');
    Check(DrawMovieLabel(Bitmap.Canvas,'端の補足文',Rect(-4,-4,100,55),DT_LEFT or DT_WORDBREAK)>0,'partially clipped label renders at frame edge');
    Objects := GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS);
    for var I := 1 to 500 do DrawMovieLabel(Bitmap.Canvas,'再生中の章名',Rect(20,20,680,150),DT_LEFT);
    Check(GetGuiResources(GetCurrentProcess,GR_GDIOBJECTS)<=Objects+1,'continuous label rendering releases temporary blend bitmaps and DCs');
  finally Bitmap.Free; end;
  var P := TRigmMovieProject.Create;
  try
    P.Width := 1920; P.Height := 1080; P.BackgroundColor := clWhite;
    var S := TRigmMovieScene.Create; P.Scenes.Add(S); S.Title := 'シーン名：新しい一歩'; S.DisplayMode := 'none';
    var C := TRigmMovieCue.Create; P.Cues.Add(C); C.Scene := S.Id; C.Subtitle := 'セリフの字幕もフチドリ付き'; C.AudioSeconds := 1;
    Bitmap := RenderComposition(P,0.05,nil);
    try Contrast(Bitmap,Rect(55,20,800,90),'composited scene title');
      BackdropPixel(Bitmap,50,18,clWhite,'composited chapter padding');
      Contrast(Bitmap,Rect(200,890,1720,1060),'composited subtitle'); SavePng(Bitmap,'outlined-composition-fullhd');
    finally Bitmap.Free; end;
    Bitmap := RenderMoviePreview(P,nil,0.05,nil,640,360);
    try Contrast(Bitmap,Rect(18,6,300,35),'scaled preview scene title'); SavePng(Bitmap,'outlined-composition-preview'); finally Bitmap.Free; end;
    S.Title := ''; S.DisplayMode := 'both'; S.Description := '画像の補足文：読みやすい表示';
    var Solid := TBitmap.Create;
    try Solid.SetSize(980,550); Solid.Canvas.Brush.Color := clAqua; Solid.Canvas.FillRect(Rect(0,0,980,550));
      SavePng(Solid,'label-scene-source'); S.Image := TPath.Combine(Root,'label-scene-source.png');
    finally Solid.Free; end;
    for var Layout in ['theme','l-left','l-right'] do begin
      var LayoutName, Direction: string; DecodeLayoutChoice(Layout,LayoutName,Direction);
      P.Layout := LayoutName; P.LDirection := Direction;
      for var Position in ['below-image','image-top','image-center','image-bottom','screen-top'] do begin
        S.DescriptionPosition := Position;
        for var Preview in [False,True] do begin
          var Description := S.Description; S.Description := '';
          if Preview then Bitmap := RenderMoviePreview(P,nil,0.05,nil,640,360) else Bitmap := RenderComposition(P,0.05,nil);
          var Area := ScaleLayoutRect(MovieDescriptionRegion(P.Layout,P.LDirection,Position),Bitmap.Width,Bitmap.Height);
          InflateRect(Area,-12,-8); var Base := Bitmap.Canvas.Pixels[Area.Left-1,Area.Top-1]; Bitmap.Free;
          S.Description := Description;
          if Preview then Bitmap := RenderMoviePreview(P,nil,0.05,nil,640,360) else Bitmap := RenderComposition(P,0.05,nil);
          try
            BackdropPixel(Bitmap,Area.Left-1,Area.Top-1,Base,'description '+Layout+' '+Position+' preview='+Preview.ToString);
            Check(ColorToRGB(Bitmap.Canvas.Pixels[55,20])=ColorToRGB(clWhite),'empty chapter stays hidden '+Layout+' '+Position+' preview='+Preview.ToString);
            SavePng(Bitmap,'description-'+Layout+'-'+Position+'-'+Preview.ToString);
          finally Bitmap.Free; end;
        end;
      end;
    end;
    P.Scenes.Clear; C.Scene := '従来形式のシーン名';
    Bitmap := RenderMovieFrame(P,nil,0.05);
    try Contrast(Bitmap,Rect(60,30,800,160),'legacy scene title'); SavePng(Bitmap,'outlined-legacy'); finally Bitmap.Free; end;
    Bitmap := TBitmap.Create;
    try
      Bitmap.SetSize(980,550); var Chart := PsdJson.ObjectText('{"kind":"bar","title":"総評チャート","maximum":5,"items":[{"label":"構成","value":4}]}');
      try DrawMovieChart(Bitmap.Canvas,Chart,Rect(0,0,980,550));
        Contrast(Bitmap,Rect(100,10,880,65),'chart title'); SavePng(Bitmap,'outlined-chart');
      finally Chart.Free; end;
    finally Bitmap.Free; end;
  finally P.Free; end;
end;

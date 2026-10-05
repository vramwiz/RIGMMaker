using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

// Deterministic manga signs: editable vector paths, rasterized at 3x resolution.
public static class MangaSigns {
    static Color Ink = Color.FromArgb(33,36,48);
    static Color Gold = Color.FromArgb(255,203,55);
    static Color Red = Color.FromArgb(255,87,92);
    static Color Blue = Color.FromArgb(75,174,255);
    static Graphics G;
    static void Shape(GraphicsPath p, Color c, float edge=7) {
        using(var white=new Pen(Color.White,edge+9))
        using(var ink=new Pen(Ink,edge))
        using(var brush=new SolidBrush(c)) {
            white.LineJoin=ink.LineJoin=LineJoin.Round;
            G.DrawPath(white,p); G.DrawPath(ink,p); G.FillPath(brush,p);
        }
    }
    static void Line(Color c,float width,params PointF[] points) {
        using(var p=new Pen(Color.White,width+7)) {
            p.StartCap=p.EndCap=LineCap.Round; p.LineJoin=LineJoin.Round; G.DrawLines(p,points);
        }
        using(var p=new Pen(c,width)) {
            p.StartCap=p.EndCap=LineCap.Round; p.LineJoin=LineJoin.Round; G.DrawLines(p,points);
        }
    }
    static void Poly(Color c,params PointF[] points) {
        using(var p=new GraphicsPath()) {p.AddPolygon(points);Shape(p,c);}
    }
    static void Text(string s,float x,float y,float w,float h,Color c,float angle=0) {
        using(var p=new GraphicsPath())
        using(var f=new FontFamily("Yu Gothic UI")) {
            p.AddString(s,f,(int)FontStyle.Bold,220,new PointF(0,0),StringFormat.GenericTypographic);
            var b=p.GetBounds();
            using(var m=new Matrix(w/b.Width,0,0,h/b.Height,x-b.X*w/b.Width,y-b.Y*h/b.Height)) p.Transform(m);
            using(var m=new Matrix()) {m.RotateAt(angle,new PointF(x+w/2,y+h/2));p.Transform(m);}
            Shape(p,c);
        }
    }
    static void Drop(float x,float y,float scale,float angle) {
        using(var p=new GraphicsPath()) {
            p.AddBezier(0,-60,10,-20,37,5,34,27);
            p.AddBezier(34,27,31,68,-30,68,-34,27);
            p.AddBezier(-34,27,-37,5,-10,-20,0,-60);
            p.CloseFigure();
            using(var m=new Matrix()) {m.Scale(scale,scale);m.Rotate(angle,MatrixOrder.Append);m.Translate(x,y,MatrixOrder.Append);p.Transform(m);}
            Shape(p,Color.FromArgb(77,206,239),6);
        }
        using(var p=new Pen(Color.FromArgb(240,255,255),5)) {p.StartCap=p.EndCap=LineCap.Round;G.DrawLine(p,x+9*scale,y+4*scale,x+12*scale,y+25*scale);}
    }
    static void Spark(float x,float y,float r,Color c) {
        Poly(c,new PointF(x,y-r),new PointF(x+r*.22f,y-r*.22f),new PointF(x+r,y),
            new PointF(x+r*.22f,y+r*.22f),new PointF(x,y+r),new PointF(x-r*.22f,y+r*.22f),
            new PointF(x-r,y),new PointF(x-r*.22f,y-r*.22f));
    }
    static void Draw(int kind,int width,int height) {
        switch(kind) {
        case 1:
            Text("!",79,37,80,207,Gold,-10);
            Line(Ink,7,new PointF(42,42),new PointF(23,22));
            Line(Ink,7,new PointF(192,66),new PointF(215,46));
            Line(Ink,6,new PointF(194,101),new PointF(224,99));
            break;
        case 2:
            Text("?",54,42,127,212,Blue,8);
            Text("?",185,22,35,60,Color.FromArgb(157,215,255),-14);
            Spark(30,158,16,Gold);
            break;
        case 3:
            Text("!",45,33,75,219,Red,-11);
            Text("?",144,41,132,216,Gold,10);
            Line(Ink,6,new PointF(306,62),new PointF(328,44));
            Line(Ink,6,new PointF(308,99),new PointF(338,98));
            break;
        case 4:
            Text("!",43,39,70,205,Red,-13);
            Text("!",158,29,76,218,Gold,12);
            Line(Ink,6,new PointF(20,78),new PointF(12,48));
            Line(Ink,6,new PointF(272,78),new PointF(286,48));
            break;
        case 5:
            // Transparent center keeps the face and hair unobstructed.
            for(int i=0;i<24;i++) {
                double a=(i*15+3)*Math.PI/180;
                double d=1.8*Math.PI/180;
                float innerX=(float)(520+205*Math.Cos(a)),innerY=(float)(310+235*Math.Sin(a));
                float rx=i%2==0?360:326, ry=i%2==0?300:278;
                Poly(i%3==0?Gold:Color.White,new PointF(innerX,innerY),
                    new PointF((float)(520+rx*Math.Cos(a-d)),(float)(310+ry*Math.Sin(a-d))),
                    new PointF((float)(520+rx*Math.Cos(a+d)),(float)(310+ry*Math.Sin(a+d))));
            }
            break;
        case 6:
            var points=new PointF[24];
            for(int i=0;i<24;i++) {
                double a=(i*15-90)*Math.PI/180;float r=i%2==0?119:67;
                points[i]=new PointF((float)(140+r*Math.Cos(a)),(float)(140+r*Math.Sin(a)));
            }
            Poly(Gold,points);
            Poly(Red,new PointF(153,57),new PointF(110,126),new PointF(151,119),
                new PointF(121,224),new PointF(184,128),new PointF(146,134));
            break;
        case 7:
            Drop(92,177,1.15f,9);Drop(187,103,.66f,27);Drop(38,58,.43f,-20);
            Line(Blue,5,new PointF(184,174),new PointF(200,194));
            Line(Blue,5,new PointF(168,197),new PointF(180,214));
            break;
        case 8:
            for(int i=0;i<8;i++) {
                float x=27+i*26,top=24+(i%3)*8,bottom=164+(i%4)*20;
                Poly(Color.FromArgb(119+i*8,96,193),new PointF(x,top),new PointF(x+9,top),new PointF(x+4,bottom));
            }
            Line(Color.FromArgb(131,105,210),7,new PointF(24,245),new PointF(45,231),
                new PointF(67,245),new PointF(89,231),new PointF(111,245),new PointF(133,231),
                new PointF(155,245),new PointF(177,231),new PointF(199,245),new PointF(221,231));
            break;
        case 9:
            using(var p=new GraphicsPath()) {
                p.AddBezier(98,202,97,167,68,157,68,112);
                p.AddBezier(68,112,68,41,190,41,190,112);
                p.AddBezier(190,112,190,157,161,167,160,202);
                p.CloseFigure();Shape(p,Gold);
            }
            Line(Ink,5,new PointF(118,192),new PointF(111,132),new PointF(130,147),new PointF(148,132),new PointF(141,192));
            using(var p=new GraphicsPath()) {p.AddRectangle(new RectangleF(98,203,63,24));Shape(p,Color.FromArgb(203,213,229),5);}
            Line(Ink,5,new PointF(108,239),new PointF(151,239));
            Line(Gold,7,new PointF(129,19),new PointF(129,4));
            Line(Gold,7,new PointF(49,49),new PointF(32,32));
            Line(Gold,7,new PointF(209,49),new PointF(226,32));
            Line(Gold,7,new PointF(39,115),new PointF(16,115));
            Line(Gold,7,new PointF(219,115),new PointF(242,115));
            break;
        }
    }
    public static void Save(string path,int kind,int width,int height) {
        using(var large=new Bitmap(width*3,height*3,PixelFormat.Format32bppArgb)) {
            using(G=Graphics.FromImage(large)) {
                G.Clear(Color.Transparent); G.SmoothingMode=SmoothingMode.AntiAlias;
                G.PixelOffsetMode=PixelOffsetMode.HighQuality; G.ScaleTransform(3,3);
                Draw(kind,width,height);
            }
            using(var output=new Bitmap(width,height,PixelFormat.Format32bppArgb)) {
                using(var g=Graphics.FromImage(output)) {
                    g.InterpolationMode=InterpolationMode.HighQualityBicubic;
                    g.CompositingQuality=CompositingQuality.HighQuality;
                    g.DrawImage(large,new Rectangle(0,0,width,height));
                }
                output.Save(path,ImageFormat.Png);
            }
        }
    }
}

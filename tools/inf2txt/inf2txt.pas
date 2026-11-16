program inf2txt;
{$mode objfpc}{$H+}
{ usage: inf2txt [-l] <inf>
  Each topic is written as a "=== title ===" line, then its text in fpGUI richtext tags.
  -l writes the topic line as "===<level>=== title" instead, <level> being the topic's contents level
  (1 = top; 0 = a topic not in the contents) - inf2txt.sh --md turns it into a markdown heading. }
uses Classes, SysUtils, HelpFile, HelpTopic;
var hf: THelpFile; t: TTopic; i: longint; s: string; imgs: TList; levels: boolean; fn: string;
begin
  levels := (ParamCount>=1) and (ParamStr(1)='-l');
  if levels then fn := ParamStr(2) else fn := ParamStr(1);
  if fn='' then begin writeln(stderr,'usage: inf2txt [-l] <inf>'); halt(1); end;
  hf := THelpFile.Create(fn);
  try
    for i := 0 to hf.TopicCount-1 do begin
      t := hf.Topics[i];
      if levels then writeln('===', t.ContentsLevel, '=== ', t.Title)
      else writeln('=== ', t.Title, ' ===');
      imgs := TList.Create;
      try s:=''; t.GetText(nil,false,false,s,imgs,nil); writeln(s);
      finally imgs.Free; end;
      writeln;
    end;
  finally hf.Free; end;
end.

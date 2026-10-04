unit RigmApiSchema;

interface
uses System.JSON, RigmModel;

function RigmCommandSchema(Page: TRigmPage): TJSONObject;

implementation
uses System.SysUtils, System.StrUtils, System.Generics.Collections, RigmJson;

function RigmCommandSchema(Page: TRigmPage): TJSONObject;
var Commands: TJSONArray;
  procedure Command(const Name, Pages, Required, Properties: string; Mutates: Boolean = True);
  var O, Args, Fields: TJSONObject; Keys: TJSONArray;
  begin
    O := TJSONObject.Create; Commands.AddElement(O); O.AddPair('command', Name); O.AddPair('pages', Pages);
    AddB(O, 'mutatesDocument', Mutates); AddB(O, 'available', (Pages = '*') or MatchStr(PageName(Page), Pages.Split([','])));
    AddB(O, 'requiresRevision', Mutates or (Name = 'select-object'));
    Args := TJSONObject.Create; O.AddPair('argsSchema', Args); Args.AddPair('type', 'object');
    Fields := ParseObject('{' + Properties + '}'); Args.AddPair('properties', Fields);
    Keys := TJSONArray.Create; Args.AddPair('required', Keys);
    if Mutates or (Name = 'select-object') then begin
      Fields.AddPair('documentId', ParseObject('{"type":"string","minLength":1}'));
      Fields.AddPair('revision', ParseObject('{"type":"string","pattern":"^[0-9]+$"}'));
      Keys.Add('documentId'); Keys.Add('revision');
    end;
    if Required <> '' then for var Key in Required.Split([',']) do Keys.Add(Key);
  end;
const
  Id = '"id":{"type":"string","minLength":1}';
  Number = '{"type":"number","minimum":-1000000,"maximum":1000000}';
  MeshMetadata = '"name":{"type":"string"},"role":{"type":"string"},"visible":{"type":"boolean"},' +
    '"locked":{"type":"boolean"},"boundaryFixed":{"type":"boolean"},"strength":{"type":"number","minimum":0,"maximum":1},' +
    '"interpolation":{"enum":["linear"]}';
  VertexArray = '{"type":"array","minItems":1,"maxItems":1024,"items":{"$ref":"#/$defs/vertex"}}';
  Triangles = '"triangles":{"type":"array","minItems":1,"maxItems":2048,"items":{"$ref":"#/$defs/triangle"}}';
  Weights = '"weights":{"type":"array","maxItems":8,"items":{"$ref":"#/$defs/weight"}}';
begin
  Result := TJSONObject.Create;
  try
    AddN(Result, 'apiVersion', 2); AddN(Result, 'envelopeSchemaVersion', 1);
    Result.AddPair('jsonSchemaDialect', 'https://json-schema.org/draft/2020-12/schema');
    Result.AddPair('routing', 'common-command'); Result.AddPair('page', PageName(Page));
    Result.AddPair('coordinates', 'canvas-center-x-right-y-down; mesh vertices are local to ancestor groups');
    Result.AddPair('atomicity', 'Each edit, batch and import commits a candidate once; errors preserve document, revision, selection and undo/redo.');
    Result.AddPair('legacyPagePipes', 'Current editing page endpoints remain available; common command pipe is stable across page changes.');
    Result.AddPair('upperBodyRig',ParseObject('{"parameterId":"bodyAngle","displayName":"上半身角度","stableLegacyId":true,"metadata":"document summary/export bodyRig.waistBoneId and upperBodyBoneId","pivot":"waist bone","bodyWeights":"spatial smooth transition above waist; below waist remains fixed","legacyOpen":"unlocked compatible rigs upgrade once as undoable unsaved changes; locked or custom incompatible rigs remain unchanged"}'));
    Result.AddPair('limits', ParseObject('{"messageBytes":60000,"pageItems":50,"verticesPerMesh":1024,"trianglesPerMesh":2048,"weightsPerVertex":8,"gridMin":2,"gridMax":16,"importBytes":8388608,"operations":2000}'));
    Result.AddPair('$defs', ParseObject(
      '{"weight":{"type":"object","required":["boneId","value"],"properties":{"boneId":{"type":"string","minLength":1},"value":{"type":"number","minimum":0,"maximum":1}}},' +
      '"vertex":{"type":"object","required":["x","y","u","v"],"properties":{"x":' + Number + ',"y":' + Number +
      ',"u":{"type":"number","minimum":0,"maximum":1},"v":{"type":"number","minimum":0,"maximum":1},' + Weights + '}},' +
      '"triangle":{"type":"object","required":["a","b","c"],"properties":{"a":{"type":"integer","minimum":0},"b":{"type":"integer","minimum":0},"c":{"type":"integer","minimum":0}}},' +
      '"operation":{"type":"object","required":["command","args"],"properties":{"command":{"type":"string"},"args":{"type":"object"}}}}'));
    Commands := TJSONArray.Create; Result.AddPair('commands', Commands);
    Command('status', '*', '', '', False);
    Command('schema', '*', '', '', False);
    Command('document', '*', '', '"section":{"enum":["summary","parts","bones","meshes","parameters","mesh-vertices","mesh-triangles"]},' + Id + ',"offset":{"type":"integer","minimum":0},"limit":{"type":"integer","minimum":1,"maximum":50}', False);
    Command('validate', '*', '', '"throughPage":{"enum":["layer","bone","mesh","preview"]},"targetId":{"type":"string"},"errorsOnly":{"type":"boolean"},"offset":{"type":"integer","minimum":0},"limit":{"type":"integer","minimum":1,"maximum":50}', False);
    Command('switch-page', '*', 'page', '"page":{"enum":["layer","bone","mesh","preview"]},"completeCurrent":{"type":"boolean","default":false}');
    Command('select-object', '*', 'id', Id, False);
    Command('save', '*', '', '"path":{"type":"string"}');
    Command('undo', '*', '', ''); Command('redo', '*', '', '');
    Command('mark-complete', '*', '', '');
    Command('batch', '*', 'operations', '"operations":{"type":"array","maxItems":2000,"items":{"$ref":"#/$defs/operation"}}');
    Command('import', 'layer,mesh', 'path', '"path":{"type":"string"}');
    Command('export', '*', '', '"root":{"type":"string"},"images":{"type":"boolean"}', False);
    Command('autofix', '*', 'issueId', '"issueId":{"type":"string"}');
    Command('ignore-issue', '*', 'issueId', '"issueId":{"type":"string"}');
    Command('request-fix', '*', 'issueId', '"issueId":{"type":"string"}');
    Command('import-png', 'layer', 'path', '"path":{"type":"string"},"parentId":{"type":"string"},"name":{"type":"string"},"role":{"type":"string"},"x":' + Number + ',"y":' + Number);
    Command('replace-png', 'layer', 'id,path', Id + ',"path":{"type":"string"}');
    Command('import-psd', 'layer', 'path', '"path":{"type":"string"},"name":{"type":"string"}');
    Command('classify-layers', 'layer', '', '');
    Command('add-group', 'layer', '', '"parentId":{"type":"string"},"name":{"type":"string"}');
    Command('update-layer', 'layer', 'id', Id + ',"name":{"type":"string"},"role":{"type":"string"},"pairId":{"type":"string"},"boneId":{"type":"string"},"tags":{"type":"string"},"referenceOnly":{"type":"boolean"},"x":' + Number + ',"y":' + Number + ',"rotation":' + Number + ',"scaleX":{"type":"number","exclusiveMinimum":0,"maximum":100},"scaleY":{"type":"number","exclusiveMinimum":0,"maximum":100},"visible":{"type":"boolean"},"opacity":{"type":"integer","minimum":0,"maximum":255},"locked":{"type":"boolean"}');
    Command('move-layer', 'layer', 'id,delta', Id + ',"delta":{"type":"integer"}');
    Command('set-parent', 'layer', 'id,parentId', Id + ',"parentId":{"type":"string"},"index":{"type":"integer"}');
    Command('delete-layer', 'layer', 'id', Id);
    Command('verify-source', 'layer', 'confirmed', '"confirmed":{"type":"boolean"}');
    Command('add-bone', 'bone', '', '"parentId":{"type":"string"},"name":{"type":"string"}');
    Command('update-bone', 'bone', 'id', Id + ',"name":{"type":"string"},"parentId":{"type":"string"},"pairId":{"type":"string"},"x":' + Number + ',"y":' + Number + ',"minAngle":' + Number + ',"maxAngle":' + Number + ',"locked":{"type":"boolean"},"paired":{"type":"boolean"}');
    for var Name in ['hide-bone', 'restore-bone', 'reset-bone'] do Command(Name, 'bone', 'id', Id + ',"paired":{"type":"boolean"}');
    Command('bind-part', 'bone', 'id,boneId', Id + ',"boneId":{"type":"string"}');
    Command('generate-mesh', 'mesh', '', '"id":{"type":"string","description":"Part ID; empty selects all image parts except reference images"},"boneId":{"type":"string"},"grid":{"type":"integer","minimum":2,"maximum":16,"default":3},"replaceExisting":{"type":"boolean","default":true}');
    Command('set-mesh', 'mesh', 'vertices,triangles', Id + ',"partId":{"type":"string"},' + MeshMetadata + ',"vertices":' + StringReplace(VertexArray, '"minItems":1', '"minItems":3', []) + ',' + Triangles);
    JO(TJSONObject(Commands[Commands.Count - 1]), 'argsSchema').AddPair('anyOf', TJSONObject.ParseJSONValue('[{"required":["id"]},{"required":["partId"]}]'));
    Command('update-mesh', 'mesh', 'id', Id + ',' + MeshMetadata);
    Command('delete-mesh', 'mesh', 'id', Id);
    Command('set-vertices', 'mesh', 'id,vertices', Id + ',"offset":{"type":"integer","minimum":0},"vertices":' + VertexArray);
    Command('update-vertex', 'mesh', 'id,vertex', Id + ',"vertex":{"type":"integer","minimum":0},"x":' + Number + ',"y":' + Number + ',"u":{"type":"number","minimum":0,"maximum":1},"v":{"type":"number","minimum":0,"maximum":1}');
    Command('add-vertex', 'mesh', 'id', Id + ',"face":{"type":"integer","minimum":0,"default":0}');
    Command('delete-vertex', 'mesh', 'id,vertex', Id + ',"vertex":{"type":"integer","minimum":0}');
    Command('set-triangles', 'mesh', 'id,triangles', Id + ',' + Triangles);
    Command('set-weights', 'mesh', 'id,weights', Id + ',"vertex":{"type":"integer","minimum":-1,"default":-1},' + Weights);
    Command('update-parameter', 'preview', 'id', Id + ',"boneId":{"type":"string"},"minimum":' + Number + ',"maximum":' + Number + ',"initial":' + Number);
    Result.AddPair('semanticChecks', TJSONObject.ParseJSONValue('["valid current documentId and revision for edits","stage preparation before page changes","visible existing bones for weights","weight sum 1 within 0.0001 and no duplicate bone IDs","nondegenerate faces with valid vertex indices","locked mesh, locked part, and fixed boundary protection","required image roles and content remain completion gates"]'));
  except Result.Free; raise; end;
end;

end.

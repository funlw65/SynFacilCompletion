{
SynFacilCompletion 1.11
======================
Por Tito Hinostroza 31/08/2015
* Se crea la rutina ExtractCompletItem(), para poder separar los campos de un ítem para
la lista de completado.
* Se mejoró el manejo del teclado y la verificación de las condiciones para cerrar la
ventana de completado.
* Se realizó la verificación de la librería en diferentes condiciones de trabajo.
* Se cambia el nombre de "patrón de apertura" a "evento de apertura", tanto en la documentación
como en el código (aún parcialmente).
* La clase TFaOpenPattern pasa a ser TFaOpenEvent y el evento AddOpenPattern() pasa a ser
AddOpenEvent() y ya no incluye el último parámetro.
* Se agrega un valor por defecto a "AfterPattern".

Pendientes:
* Verificar el correcto funcionamiento de todas las opciones,
* Hacer que las listas se guarden en los patrones de apertura, como referencias a la lista
en lugar de copiar sus ítems.
* Incluir una forma simplficada de la forma <OpenOn AfterIdentif="Alter">, para simplificsr
la deifnición clásica.
* Incluir el manejo de las ventanas de tipo "Tip", como ayuda para los parámetros de las
funciones.
* Hacer que la ventana de completado haga seguimiento del cursor, cuando este retrocede
mucho en un identificador.
* Incluir un método en TFaOpenPattern, para extraer elementos de una cadena y así
simplificar AddOpenPattern().
* Incluir íconos en la visualización de la ventana de completado.


En esta versión, se corrigen algunos errores de la versión 1.1 y se agregan pequeñas
funcionalidades pendientes. Además se ha realizado una verificación más detallada de
algunos casos de uso y se ha reordenado el código. la documentación ha sido ordenada
y se cambia el nombre de Patrón de apertura para hablar ahora de evento de apertura.

Descripción
============
Unidad que expande al resaltador TSynFacilSyn, para que pueda soportar configuraciones
de autocompletado de texto.

Se usa de forma similar a SynFacilSyn. Se debe crear un resaltador, pero ahora de la
clase TSynFacilComplet:

uses ... , SynFacilCompletion;

procedure TForm1.FormShow(Sender: TObject);
begin
 //configure highlighter
  hlt := TSynFacilComplet.Create(self);  //my highlighter
  SynEdit1.Highlighter := hlt;  //optional if we are going to use SelectEditor()
  hlt.LoadFromFile('./languages/ObjectPascal.xml');  //load syntax
  hlt.SelectEditor(SynEdit1);  //assign to editor
end;

Luego se debe interceptar los evento KeyUp y UTF8KeyPress, del SynEdit:

procedure TForm1.SynEdit1KeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  hlt.KeyUp(Sender, Key, Shift);
end;

procedure TForm1.SynEdit1UTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
begin
  hlt.UTF8KeyPress(Sender, UTF8Key);
end;

Y se debe terminar correctamente:

procedure TForm1.FormDestroy(Sender: TObject);
begin
  hlt.UnSelectEditor;   //release editor (only necessary if we are to call to SelectEditor(), again)
  hlt.Free;  //destroy the highlighter
end;

Cuando se desea desaparecer la ventana de ayuda contextual por algún evento, se debe
llamar a CloseCompletionWindow().

}
unit SynFacilCompletion;
{$mode objfpc}{$H+}
//{$define Verbose}
interface
uses
  Classes, SysUtils, fgl, Dialogs, XMLRead, DOM, LCLType, Graphics,
  SynEdit, SynEditHighlighter, SynEditTypes, SynEditKeyCmds, Lazlogger,
  SynFacilHighlighter, SynFacilBasic, SynCompletion;

type
  TFaTokInfoPtr = ^TFaTokInfo;
  TFaCompletItem = record
    text   : string;   //etiqueta a mostrar en el menú
    content: string;   //contenido a reemplazar
    descrip: string;   //descripción del campo
    OffCur : TPoint;   //desplzamiento del cursor después de realizar el reemplazo
  end;
  TFaCompletItemPtr = ^TFaCompletItem;
  TFaCompletItems = array of TFaCompletItem;

  //Filtros que se pueden aplicar a la lista mostrada
  TFaFilterList = (
    fil_None,           //Sin filtro. Muestra todos
    fil_LastTok,      //por el tokem -1
    fil_LastTokPart,  //por el token -1, hasta donde está el cursor
    fil_LastIdent,    //por el identificador anterior (usa su propia rutina para identifificadores)
    fil_LastIdentPart //similar pero toma hasta el cursor
  );

  //Tipo de Elemento del patrón
  TFaTPatternElementKind = (
    pak_none,      //tipo no definido
    pak_String,    //es literal cadena
    pak_Identif,   //es token identificador (tkKeyword, tkIndetifier, ...)
    pak_NoIdentif, //no es token identificador
    pak_TokTyp,    //es un tipo específico de token
    pak_NoTokTyp   //no es un tipo específico de token
  );
  //Elemento del patrón
  TFaPatternElement = record
    patKind: TFaTPatternElementKind;
    str    : string;          //valor, cuando es del tipo pak_String
    toktyp : TSynHighlighterAttributes;  //valor cuando es de tipo pak_TokTyp o pak_NoTokTyp
  end;


  //Entorno del cursor
  { TFaCursorEnviron }
  TFaCursorEnviron = class
  private
    hlt: TSynFacilSyn;        //referencia al resaltador que lo contiene
    tokens   : TATokInfo;     //lista de tokens actuales
    StartIdentif : integer;   //inicio de identificador
    procedure UpdateStartIdentif;
  public
    inMidTok : boolean;        //indica si el cursor está en medio de un token
    tok0     : TFaTokInfoPtr;  //referencia al token actual.
    tok_1    : TFaTokInfoPtr;  //referencia al token anterior.
    tok_2    : TFaTokInfoPtr;  //referencia al token anterior a tok_1.
    tok_3    : TFaTokInfoPtr;  //referencia al token anterior a tok_2.
    CurX     : Integer;        //posición actual del cursor
    CurY     : Integer;        //posición actual del cursor
    curLine  : string;         //línea actual de exploración
    curBlock : TFaSynBlock;    //referencia al bloque actual
    caseSen  : boolean;        //indica el estado de caja actual
    procedure LookAround(ed: TSynEdit; CaseSen0: boolean);
    //Las siguientes funciones, deben llaamrse después de lamar a LookAround()
    function HaveLastTok: boolean;
    function LastTok: string;
    function LastTokPart: string;
    function HaveLastIdent: boolean;
    function LastIdent: string;
    function LastIdentPart: string;
    procedure ReplaceLastTok(ed: TSynEdit; newStr: string);
    procedure ReplaceLastIden(ed: TSynEdit; newStr: string);
  public
    constructor Create(hlt0: TSynFacilSyn);
  end;

  //Acciones válidas que se realizarán al seleccionar un ítem
  TFAPatAction = (
    pac_None,       //no se realiza ninguna acción
    pac_Default,    //acción pro defecto
    pac_Insert,     //se inserta el texto seleccionado en la posición del cursor
    pac_Rep_LastTok //se reemplaza el token anterior
  );
  //Objeto evento de apertura
  { TFaOpenEvent }
  TFaOpenEvent = class
  private
    hlt: TSynFacilSyn;  //refrencia al resaltador que lo contiene
    Items: array of TFaCompletItem;   //lista de las palabras disponibles para el completado
    Avails: array of TFaCompletItemPtr;  {referencia a los ítems a cargar cuando se active el
                                          patrón. Se usa punteros para no duplicar datos}
    {Los índices de elem [] representan posiciones relativas de tokens
      [0]  -> Token que está justo después del cursor (token actual)
      [-1] -> Token que está antes del token actual
      [-2] -> Token que está antes del token [-1]
      [-3]  -> Token que está antes del token [-2])
    }
    elem : array[-3..0] of TFaPatternElement;
    nBef : integer;   //número de elementos válidos haste el ítem 0 (puede ser 0,1,2 o 3)
    nAft : integer;   //número de elementos válidos depués del ítem 0 (puede ser 0 o 1)
    function MatchPatternElement(nPe: integer; tokX: TFaTokInfoPtr;
      CaseSens: boolean): boolean;
    function MatchPatternBefore(const curEnv: TFaCursorEnviron): boolean;
    function MatchPatternAfter(const curEnv: TFaCursorEnviron): boolean;
    function MatchPattern(const curEnv: TFaCursorEnviron): boolean;
  public
    name  : string;    //nombre del evento de apertura
    startX: integer;   //posición inicial del token o identificador de trabajo
    filter: TFaFilterList;
    block : TFaSynBlock;  //bloque donde es válido
    Action: TFAPatAction;  //Acción al seleccionar lista
    function ExtractElem(var pat: string): string;
    procedure ShiftPatterns;  //Desplaza los elemntos
    procedure DoDefaultAction(ed: TSynEdit; env: TFaCursorEnviron; newStr: string);
    procedure DoAction(ed: TSynEdit; env: TFaCursorEnviron; itemSel: string);
    procedure FillFilteredIn(const env: TFaCursorEnviron; lst: TStrings); //Llena Items en una lista
    //manejo de ítems
    procedure LoadItems(const curEnv: TFaCursorEnviron);
    procedure AddItem(txt: string);
    procedure AddItems(lst: TStringList; blk: TFaSynBlock);
    procedure AddItems(const lItems: TFaCompletItems);
    procedure AddItems(list: string; blk: TFaSynBlock);
    procedure ClearItems;
  public
    constructor Create(hlt0: TSynFacilSyn);
  end;

  //Lista de patrones
  TFaOpenEvents = specialize TFPGObjectList<TFaOpenEvent>;

  //Objeto lista para completado
  { TFaCompletionList }
  TFaCompletionList = class
    Name : string;
    Items: array of TFaCompletItem; //lista de las palabras disponibles
    procedure AddItems(list: string);
    procedure CopyItemsTo(sList: TStrings);
  end;

  //Colección de listas
  TFaCompletionLists = specialize TFPGObjectList<TFaCompletionList>;

type
  //clase personalizada para el completado
  { TSynCompletionF }
  TSynCompletionF = class(TSynCompletion)
    function OnSynCompletionPaintItem(const AKey: string; ACanvas: TCanvas; X,
      Y: integer; IsSelected: boolean; Index: integer): boolean;

  private
    function PaintCompletionItem(const AKey: string; ACanvas: TCanvas; X, Y,
      MaxX: integer; ItemSelected: boolean; Index: integer;
      aCompletion: TSynCompletion): TPoint;
  public
    procedure Refresh;
    constructor Create(AOwner: TComponent); override;
  end;

  { TSynFacilComplet }
  //clase principal
  TSynFacilComplet = class(TSynFacilSyn)
    procedure FormKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure OnCodeCompletion(var Value: string; SourceValue: string;
      var SourceStart, SourceEnd: TPoint; KeyChar: TUTF8Char; Shift: TShiftState);
    procedure OnExecute(Sender: TObject);
    procedure FormUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
  protected
    ed        : TSynEdit;        //referencia interna al editor
    MenuComplet: TSynCompletionF;//menú contextual
    curEnv   : TFaCursorEnviron;  //entorno del cursor

    utKey         : TUTF8Char;     //tecla pulsada
    vKey          : word;          //código de tecla virtual
    vShift        : TShiftState;   //estado de shift
    SpecIdentifiers: TArrayTokSpec;
    SearchOnKeyUp : boolean;       //bandera de control
    function CheckForClose: boolean;
    procedure FillCompletMenuFiltered;
    procedure OpenCompletionWindow;
    procedure ProcCompletionLabel(nodo: TDOMNode);
    procedure ReadSpecialIdentif;
  private  //manejo de patrones de apertura
    OpenPatterns: TFaOpenEvents; //lista de patrones de apertura
    CurOpenPat  : TFaOpenEvent;    //evento de apertura que se aplica en el momento
    CompletLists: TFaCompletionLists;  //colección de listas de compleatdo
    function FindOpenEventMatching: TFaOpenEvent;
    procedure ProcXMLOpenOn(nodo: TDOMNode);
  public
    CompletionOn: boolean;  //activa o desactiva el auto-completado
    SelectOnEnter: boolean;   //habilita la selección con enter
    CaseSensComp: boolean;     //Uso de caja, en autocompletado
    OpenOnKeyUp: boolean;   //habilita que se abra automáticamente al soltar una tecla
    function AddOpenEvent(AfterPattern, BeforePattern: string;
      filter: TFaFilterList): TFaOpenEvent;
    function AddComplList(lstName: string): TFaCompletionList;
    function GetListByName(lstName: string): TFaCompletionList;
    procedure LoadFromFile(Arc: string); override;
    function LoadSyntaxFromPath(SourceFile: string; path: string;
      CaseSens: boolean=false): string;
    procedure SelectEditor(ed0: TSynEdit);  //inicia la ayuda contextual
    procedure UnSelectEditor;  //termina la ayuda contextual con el editor
    procedure UTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure KeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CloseCompletionWindow;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  //utilidades
  function ReadExtenFromXML(XMLfile: string): string;
  function XMLFileHaveExten(XMLfile: string; exten: string;
                CaseSens: boolean = false): boolean;

implementation
uses SynEditMiscProcs;

const
//  ERR_ATTRIB_NO_EXIST = 'Atributo %s no existe. (etiqueta <COMPLETION ...>)';
//  ERR_FILTER_NO_EXIST = 'Filtro %s no existe. (etiqueta <OpenOn ...>)';
//  ERR_INVAL_LAB_COMP = 'Etiqueta %s no válida para etiqueta <COMPLETION ...>';
//  ERR_INVAL_BLK_NAME = 'Nombre de bloque inválido.';
//  ERROR_LOADING_ = 'Error loading: ';
//  ERR_PAR_BEF_PATT = 'Error en parámetro "BeforePattern"';
//  ERR_PAR_AFT_PATT = 'Error en parámetro "AfterPattern"';

  ERR_ATTRIB_NO_EXIST = 'Attribute %s doesn''t exist. (label <COMPLETION ...>)';
  ERR_FILTER_NO_EXIST = 'Filter %s doesn''t exist. (label <OpenOn ...>)';
  ERR_ACTION_NO_EXIST = 'Action %s doesn''t exist. (label <OpenOn ...>)';
  ERR_INVAL_LAB_OPNON = 'Invalid label %s for <OpenOn ...>';
  ERR_INVAL_LAB_COMP = 'Invalid label %s for  <COMPLETION ...>';
  ERR_INVAL_BLK_NAME = 'Invalid block name.';
  ERROR_LOADING_ = 'Error loading: ';
  ERR_PAR_BEF_PATT = 'Error in parameter "BeforePattern"';
  ERR_PAR_AFT_PATT = 'Error in parameter "AfterPattern"';

  //Constantes para manejar parámetros de <OpenOn>
  WORD_CHARS = ['a'..'z','0'..'9','A'..'Z','_'];
  STR_DELIM = ['''','"'];
  ALL_IDENTIF = 'AllIdentifiers';
  //Para el reconocimiento de identificadores, cuando se usa "fil_LastIdent" y "fil_LastIdentPart"
  CHAR_STRT_IDEN = ['a'..'z','A'..'Z','_'];
  CHAR_BODY_IDEN = CHAR_STRT_IDEN + ['0'..'9'];

function ReadExtenFromXML(XMLfile: string): string;
//Lee las extensiones que tiene definidas un archivo de sintaxis.
var doc: TXMLDocument;
  atri: TDOMNode;
  i: Integer;
begin
  try
    Result := '';   //por defecto
    ReadXMLFile(doc, XMLfile);  //carga archivo
    //busca el parámetro "ext"
    for i:= 0 to doc.DocumentElement.Attributes.Length-1 do begin
      atri := doc.DocumentElement.Attributes.Item[i];
      if UpCase(atri.NodeName) = 'EXT' then begin
        Result := trim(atri.NodeValue);  //valor sin espacios
      end;
    end;
    doc.Free;  //libera
  except
    on E: Exception do begin
      ShowMessage(ERROR_LOADING_ + XMLfile + #13#10 + e.Message);
      doc.Free;
    end;
  end;
end;
function XMLFileHaveExten(XMLfile: string; exten: string;
                CaseSens: boolean = false): boolean;
//Indica si un archivo XML de sintaxis, tiene definida la extensión que se indica
//La comparación se puede hacer con o sin diferecnia de caja
var
  lext: TStringList;
  s: String;
  tmp: String;
begin
  Result := false;  //por defecto
  lext:= TStringList.Create;  //crea lista
  tmp := ReadExtenFromXML(XMLfile);  //lee archivo
  lext.DelimitedText:=' ';
  lext.Text:=tmp;  //divide
  //busca de acuerdo a la caja
  if CaseSens then begin
    for s in lext do begin
      if s = exten then begin
        //encontró
        Result := true;
        lext.Free;
        exit;
      end;
    end;
  end else begin
    for s in lext do begin
      if Upcase(s) = Upcase(exten) then begin
        //encontró
        Result := true;
        lext.Free;
        exit;
      end;
    end;
  end;
  //No enecontró
  lext.Free;
end;
procedure ExtractCompletItem(item: string; var cpIt:TFaCompletItem);
{Recibe una cadena que representa a un ítem y de el extrae los campos, si es que vinieran
codificados. El formato de la codificiacón es:
 <texto a mostrar> | <texto a reemplazar> | <descripción>
Además se soportan las siguienets ecuencias de escape:
\n -> salto de línea
\c -> posición en donde se debe dejar el cursor
\| -> caracter "|"
}
  function EscapeBefore(i: integer): boolean; inline;
  begin
    if i<1 then exit(false);
    if item[i-1] = '\' then exit(true) else exit(false);
  end;
  function ExecEscape(const s: string): string;
  begin
    Result := StringReplace(s, '\n', LineEnding, [rfReplaceAll]);
    Result := StringReplace(Result, '\t', #9, [rfReplaceAll]);
    Result := StringReplace(Result, '\|', '|', [rfReplaceAll]);
    //Se debería implementar un método más rápido
    {setlength(Result, length(s));  //hace espacio
    j := 1;
    i := 1;
    while i <= length(s) do begin
      if s[i]='\' then begin

      end else begin
        Result[j] := s[i];
        inc(j);
      end;
      inc(i);
    end;}
  end;
  function ExtractField(var str: string): string;
  {Extrae un campo de la cadena. El campo debe estar delimitado con "|"}
  var
    psep: SizeInt;
  begin
    psep := pos('|', item);
    if (psep = 0) or EscapeBefore(psep) then begin
      //no hay separador de campos, es un caso simple
      Result := str;
      str := '';
    end else begin
      //hay separador
      Result:=copy(item,1,psep-1);
      str := copy(str, psep+1, length(str));
    end;
  end;

var
  txt1, txt2: String;
begin
  txt1 := ExtractField(item);
  if item='' then begin
    //solo hay un campo
    cpIt.text    :=ExecEscape(txt1);
    cpIt.content :=cpIt.text;
    cpIt.descrip  :='';
    cpIt.OffCur.x :=0;
    cpIt.OffCur.y :=0;
  end else begin
    //hay al menos otro campo
    txt2 := ExtractField(item);
    if item = '' then begin
      //hay solo dos campos
      cpIt.text    :=ExecEscape(txt1);
      cpIt.content :=ExecEscape(txt2);
      cpIt.descrip :='';
      cpIt.OffCur.x:=0;
      cpIt.OffCur.y:=0;
    end else begin
      //has 3 o más campos
      cpIt.text    :=ExecEscape(txt1);
      cpIt.content :=ExecEscape(txt2);
      cpIt.descrip :=ExecEscape(item);
      cpIt.OffCur.x:=0;
      cpIt.OffCur.y:=0;
    end;
  end;
end;
{ TFaCompletionList }
procedure TFaCompletionList.AddItems(list: string);
//Agrega una lista de ítems, separados por espacios, a la lista de completado
var
  n: Integer;
  lst: TStringList;
  i: Integer;
begin
  //divide
  lst := TStringList.Create;
  lst.Delimiter := ' ';
  lst.DelimitedText := list;

  //agrega
  n := high(Items)+1;  //tamaño de matriz
  setlength(Items,n+lst.Count);
  for i:= 0 to lst.Count-1 do begin
    ExtractCompletItem(lst[i], Items[n+i]);
  end;
  lst.Destroy;
end;
procedure TFaCompletionList.CopyItemsTo(sList: TStrings);
//Agrega su contendio a la lista "sList"
var
  i: Integer;
begin
  for i:= 0 to High(items) do begin
    sList.Add(items[i].text);
  end;
end;

{ TFaCursorEnviron }
constructor TFaCursorEnviron.Create(hlt0: TSynFacilSyn);
begin
  hlt := hlt0;
end;
procedure TFaCursorEnviron.LookAround(ed: TSynEdit; CaseSen0: boolean);
{Analiza el estado del cursor en el editor. Se supone que se debe llamar, después de
 actualizar el editor. Actualiza: PosiCursor, curBlock, tok0, tok_1, tok_2
 y tok_3. Utiliza punteros, para evitar perder tiempo creando copias.}
var
  iTok0    : integer;       //índice al token actual
begin
  caseSen:=CaseSen0;  //actualiza estado
  //valores por defecto
  curBlock := nil;
  //explora la línea con el resaltador
  hlt.ExploreLine(ed.CaretXY, tokens, iTok0);
  curLine := ed.Lines[ed.CaretY-1]; { TODO : Para evitar perder tiempo copiando la línea actual, se
                                   podría usar una versión de ExploreLine() que devuelva la línea
                                   actual, ya que esta copia es creada ya dentro de ExploreLine()
                                   y mejor aún que explore solo hasta el token[0]}
  if iTok0=-1 then exit;   //no ubica al token actual
  tok0 := @tokens[iTok0];    //lee token actual token[0]
  CurX := ed.LogicalCaretXY.x;  //usa posición física para comparar
  CurY := ed.LogicalCaretXY.y;
  inMidTok := tokens[iTok0].posIni+1 <> CurX;  //actualiza bandera
  //actualiza tok_1
  if inMidTok then begin
    tok_1 := @tokens[iTok0];
    if iTok0>0 then tok_2 := @tokens[iTok0-1]
    else tok_2 := nil;
    if iTok0>1 then tok_3 := @tokens[iTok0-2]
    else tok_3 := nil;
  end else begin
    if iTok0>0 then tok_1 := @tokens[iTok0-1]
    else tok_1 := nil;
    if iTok0>1 then tok_2 := @tokens[iTok0-2]
    else tok_2 := nil;
    if iTok0>2 then tok_3 := @tokens[iTok0-3]
    else tok_3 := nil;
  end;
  //captura "curBlock"
  curBlock := tok0^.curBlk;  //devuelve bloque
  {$IFDEF Verbose}
  DbgOut('  LookAround:(');
  if tok_3<>nil then DbgOut(tok_3^.TokTyp.Name+',');
  if tok_2<>nil then DbgOut(tok_2^.TokTyp.Name+',');
  if tok_1<>nil then DbgOut(tok_1^.TokTyp.Name+',');
  if tok0<>nil then DbgOut(tok0^.TokTyp.Name);
  debugln(')');
  {$ENDIF}
end;
//Las siguientes funciones, deben llamarse después de lamar a LookAround()
function TFaCursorEnviron.HaveLastTok: boolean; inline;
begin
  Result := (tok_1 <> nil);
end;
function TFaCursorEnviron.LastTok: string; inline;
{Devuelve el último token}
begin
  Result := tok_1^.txt;
end;
function TFaCursorEnviron.LastTokPart: string; inline;
{Devuelve el último token, truncado a la posición del cursor}
begin
//  Result := copy(tok0^.txt,1,CurX-tok0^.posIni-1);
  Result := copy(tok_1^.txt, 1, CurX-tok_1^.posIni-1);
end;
procedure TFaCursorEnviron.UpdateStartIdentif;
{Actualiza el índice al inicio del identificador anterior, a la posición actual del cursor.
 Este es un algoritmo, un poco especial, porque los identificadores no se
 definen para explorarlos hacia atrás.}
var
  i: Integer;
begin
  StartIdentif := -1;   //valor por defecto
  if CurX<=1 then exit;  //está al inicio
  i:= CurX-1;  //caracter anterior al cursor
  {Se asume que el cursor, está después de un identificador y retrocede por los
  caracteres hasta encontrar un caracter que pueda ser inicio de identificador}
  while (i>0) and (curLine[i] in CHAR_BODY_IDEN) do begin
    if curLine[i] in CHAR_STRT_IDEN then begin
       StartIdentif := i;    //guarda una posible posición de inicio
    end;
    dec(i);
  end;
end;
function TFaCursorEnviron.HaveLastIdent: boolean;
{Indica si hay un identificador antes del cursor. Debe llamarse siempre antes de
 usar LastIdent().}
begin
  UpdateStartIdentif;
  Result := (StartIdentif <> -1);
end;
function TFaCursorEnviron.LastIdent: string;
{Devuelve el identificador anterior al cursor. Debe llamarse siempre despues de llamar
 a HaveLastIdent}
var
  i: Integer;
begin
  {Ya sabemos que hay identificador hasta antes del cursor, ahora debemos ver, hasta
   dónde se extiende}
  i := CurX;
  while curLine[i] in CHAR_BODY_IDEN do  //no debería ser necesario verificar el final
    inc(i);
  Result := copy(curLine, StartIdentif, i-StartIdentif+1);
end;
function TFaCursorEnviron.LastIdentPart: string;
{Devuelve el identificador anterior al cursor. Debe llamarse siempre despues de llamar
 a HaveLastIdent}
begin
  Result := copy(curLine, StartIdentif, CurX-StartIdentif);
end;
procedure TFaCursorEnviron.ReplaceLastTok(ed: TSynEdit; newStr: string);
{Reemplaza el último token}
var
  Pos1, Pos2: TPoint;
begin
  Pos1 := Point(tok_1^.posIni + 1, CurY);
  Pos2 := Point(tok_1^.posIni + tok_1^.length+1, CurY);
  ed.TextBetweenPoints[Pos1,Pos2] := NewStr;  //usa TextBetweenPoints(), para poder deshacer
end;
procedure TFaCursorEnviron.ReplaceLastIden(ed: TSynEdit; newStr: string);
{Reemplaza el último identificador. Debe llamarse siempre despues de llamar
 a HaveLastIdent}
var
  Pos1, Pos2: TPoint;
  i: Integer;
begin
  Pos1 := Point(StartIdentif, CurY);
  i := CurX;
  while curLine[i] in CHAR_BODY_IDEN do  //no debería ser necesario verificar el final
    inc(i);
  Pos2 := Point(i, CurY);
  ed.TextBetweenPoints[Pos1,Pos2] := NewStr;  //usa TextBetweenPoints(), para poder deshacer
end;

{ TFaOpenEvent }
function TFaOpenEvent.ExtractElem(var pat: string): string;
{Extrae un elemento de una cadena de patrón. La cadena puede ser algo así como
 "Identifier,'.',AllIdentifiers" }
var
  i: Integer;
  ci: Char;
begin
  pat := trim(pat);     //quita espacios
  if pat='' then exit('');  //no hay más elementos
  if pat[1] in WORD_CHARS then begin
    //Es un identificador.
    //Captura nombre de tipo de token o la cadena especial "AllIdentifiers"
    i := 1;
    while (i<=length(pat)) and (pat[i] in WORD_CHARS)  do begin
      inc(i);
    end;
    //if i>length(pat) then exit('#');   //hay error
  end else if pat[1] in STR_DELIM then begin
    //es un literal cadena
    ci := pat[1];   //caracter inicial
    i := 2;
    while (i<=length(pat)) and (pat[i] <> ci) do begin
      inc(i);
    end;
    if i>length(pat) then exit('#');   //hay error
    inc(i);
  end else begin
    exit('#');   //hay error
  end;
  Result := copy(pat, 1,i-1);  //extrae cadena
  pat := copy(pat, i, 200); //recorta
  pat := trim(pat);     //quita espacios
  //quita posible coma final
  if (pat<>'') and (pat[1] = ',') then
    pat := copy(pat, 2, 200);
end;
procedure TFaOpenEvent.ShiftPatterns;
{Desplaza un elemento del patrón, poniendo el de menor índice en pak_none. No toca el de
índice 0}
begin
  elem[-1] := elem[-2];
  elem[-2] := elem[-3];
  elem[-3].patKind := pak_none;
  dec(nBef);  //actualiza elementos anteriores válidos
end;
procedure TFaOpenEvent.DoDefaultAction(ed: TSynEdit; env: TFaCursorEnviron; newStr: string);
{Reemplaza el token o dientificador de trabajo actual}
begin
  case Filter of
  fil_None: ;  //no hay elemento de selcción
  fil_LastTok,
  fil_LastTokPart: begin  //trabaja con el último token
      if env.HaveLastTok then
        env.ReplaceLastTok(ed, newStr);
      //posiciona al cursor al final de la palabra reemplazada
      ed.LogicalCaretXY :=Point(env.tok_1^.posIni+length(NewStr)+1,ed.CaretY);  //mueve cursor
    end;
  fil_LastIdent,
  fil_LastIdentPart: begin  //trabaja con el úmtimo identificador
      if env.HaveLastIdent then
        env.ReplaceLastIden(ed, newStr);
      //posiciona al cursor al final de la palabra reemplazada
      ed.LogicalCaretXY :=Point(env.StartIdentif+length(NewStr),ed.CaretY);  //mueve cursor
    end;
  end;
end;
procedure TFaOpenEvent.DoAction(ed: TSynEdit; env: TFaCursorEnviron;
  itemSel: string);
{Ejecuta la acción que se tenga definido para el evento de apertura}
var
  Pos1: TPoint;
  Pos2: TPoint;
begin
  case Action of
  pac_None:;  //no ahce nada
  pac_Default:  //acción por defecto
    DoDefaultAction(ed, env, itemSel);
  pac_Insert:  begin //inserta
      Pos1 := Point(env.CurX, env.CurY);
      Pos2 := Point(env.CurX, env.CurY);
      ed.TextBetweenPoints[Pos1,Pos2] := itemSel;
      ed.LogicalCaretXY :=Point(ed.CaretX+length(itemSel),ed.CaretY);  //mueve cursor
    end;
  pac_Rep_LastTok: begin
      if env.HaveLastTok then
        env.ReplaceLastTok(ed, itemSel);
      //posiciona al cursor al final de la palabra reemplazada
      ed.LogicalCaretXY :=Point(env.tok_1^.posIni+length(itemSel)+1,ed.CaretY);  //mueve cursor
  end;
  {Se pueden completar más acciones}
  else
    DoDefaultAction(ed, env, itemSel);
  end;
end;
procedure TFaOpenEvent.FillFilteredIn(const env: TFaCursorEnviron; lst: TStrings);
{Filtra los ítems que contiene (usando "env") y los pone en la lista indicada}
  procedure FilterBy(const str: string);
  //Llena el menú de completado a partir de "Avails", filtrando solo las
  //palabras que coincidan con "str"
  var
    l: Integer;
    i: Integer;
    str2: String;
  begin
    l := length(str);
    //Genera la lista que coincide
    if env.caseSen then begin
      for i:=0 to high(Avails) do begin
        //esta no es la forma más eficiente de comparar, pero sirve por ahora.
        if str = copy(Avails[i]^.text,1,l) then
//          lst.Add(Avails[i]^.text);
          lst.AddObject(Avails[i]^.text, nil);
      end;
    end else begin  //ignora la caja
      str2 := UpCase(str);
      for i:=0 to high(Avails) do begin
        if str2 = upcase(copy(Avails[i]^.text,1,l)) then begin
//          lst.Add(Avails[i]^.text);
          lst.AddObject(Avails[i]^.text, nil);
        end;
      end;
    end;
  end;

var
  i: Integer;
begin
  case Filter of
  fil_None: begin  //agrega todos
      for i:=0 to high(Avails) do begin  //agrega sus ítems
        lst.Add(Avails[i]^.text);
      end;
    end;
  fil_LastTok: begin  //último token
      if env.HaveLastTok then
        FilterBy(env.LastTok);
    end;
  fil_LastTokPart: begin  //último token hasta el cursor
      if env.HaveLastTok then
        FilterBy(env.LastTokPart);
    end;
  fil_LastIdent: begin  //último token
      if env.HaveLastIdent then
        FilterBy(env.LastIdent);
    end;
  fil_LastIdentPart: begin  //último token hasta el cursor
      if env.HaveLastIdent then
        FilterBy(env.LastIdentPart);
    end;
  end;
end;
//manejo de ítems
procedure TFaOpenEvent.LoadItems(const curEnv: TFaCursorEnviron);
{Carga todos los ítems con los que se va a trabajar en Avails[]. Los que se usarán para
 posteriormente filtrarse y cargarse al menú de completado.}
  procedure FilterByChar(const c: char);
  {Filtra la lista Items[], usando un caracter}
  var
    i: Integer;
    cu: Char;
    nAvails: Integer;
  begin
    SetLength(Avails, high(Items)+1);  //tamaño máximo
    nAvails := 0;
    if curEnv.caseSen then begin
      for i:=0 to high(Items) do begin
        if (Items[i].text<>'') and  (Items[i].text[1] = c) then begin
          Avails[nAvails] := @Items[i];
          Inc(nAvails);
        end;
      end;
    end else begin
      cu := UpCase(c);
      for i:=0 to high(Items) do begin
        if (Items[i].text<>'') and  (upcase(Items[i].text[1]) = cu) then begin
          Avails[nAvails] := @Items[i];
          Inc(nAvails);
        end;
      end;
    end;
    SetLength(Avails, nAvails);  //elimina adicionales
    {Si se quisiera acelerar aún más el proceso, se puede pública "nAvails" y no truncar Avails[]}
  end;
var
  i: Integer;
begin
  case filter of
  fil_None: begin  //no hay filtro
    //copia todas las referecnias
    SetLength(Avails, high(Items)+1);
    for i:=0 to high(Items) do begin
      Avails[i] := @Items[i];
    end;
    startX := curEnv.CurX;   //como no hay palabra de trabajo
  end;
  fil_LastTok,
  fil_LastTokPart: begin    //se usará el último token
    if curEnv.HaveLastTok then begin
      //hay un token anterior
      startX := curEnv.tok_1^.posIni;   //inicio del token
      FilterByChar(curEnv.LastTok[1]);   //primer caracter como filtro (peor caso)
    end;
  end;
  fil_LastIdent,
  fil_LastIdentPart: begin    //se usará el último identif.
    if curEnv.HaveLastIdent then begin
      //hay un token anterior
      startX := curEnv.StartIdentif;   //es fácil sacra el inicio del identificador
      FilterByChar(curEnv.LastIdentPart[1]);  //primer caracter como filtro (peor caso)
    end;
  end;
  else   //no debería pasar
    SetLength(Avails, 0);
    startX := curEnv.CurX;
  end;
  {$IFDEF Verbose}
  debugln('  Cargados: '+IntToStr(High(Avails)+1)+ ' ítems.')
  {$ENDIF}
end;
function TFaOpenEvent.MatchPatternElement(nPe: integer; tokX: TFaTokInfoPtr;
                CaseSens: boolean): boolean;
{Verifica el elemento de un patrón, coincide con un token de tokens[]. }
var
  pe: TFaPatternElement;
begin
  pe := elem[nPe];  //no hay validación. Por velocidad, podría sermejor un puntero.
  if tokX = nil then exit(false); //no existe este token
  case pe.patKind of
  pak_none:           //*** No definido.
    exit(true);  //No debería llegar aquí.
  pak_String: begin   //*** Es una cadena
    if CaseSens then begin //comparación con caja
      if tokX^.txt = pe.str then exit(true)
      else exit(false);
    end else begin    //comparación sin caja
      if UpCase(tokX^.txt) = UpCase(pe.str) then exit(true)
      else exit(false);
    end;
  end;
  pak_Identif: begin  //*** Es identificador
    Result := tokX^.IsIDentif;
  end;
  pak_NoIdentif: begin
    Result := not tokX^.IsIDentif;
  end;
  pak_TokTyp: begin   //*** Es un tipo específico de token
    Result := pe.toktyp = tokX^.TokTyp;
  end;
  pak_NoTokTyp: begin   //*** Es un tipo específico de token
    Result := not (pe.toktyp = tokX^.TokTyp);
  end;
  end;
end;
function TFaOpenEvent.MatchPatternBefore(const curEnv: TFaCursorEnviron
  ): boolean;
{Verifica si el patrón indicado, cumple con las condiciones actuales (before)}
begin
  case nBef of
  0: begin  //no hay elementos, siempre cumple                  |
    exit(true);
  end;
  1: begin  //hay elem[-1]
     Result := MatchPatternElement(-1, curEnv.tok_1, curEnv.caseSen);
  end;
  2: begin  //hay elem[-2],elem[-1]
        Result := MatchPatternElement(-1, curEnv.tok_1, curEnv.caseSen) and
                  MatchPatternElement(-2, curEnv.tok_2, curEnv.caseSen);
  end;
  3: begin  //hay elem[-3],elem[-2],elem[-1]
        Result := MatchPatternElement(-1, curEnv.tok_1, curEnv.caseSen) and
                  MatchPatternElement(-2, curEnv.tok_2, curEnv.caseSen) and
                  MatchPatternElement(-3, curEnv.tok_3, curEnv.caseSen);
  end;
  end;
end;
function TFaOpenEvent.MatchPatternAfter(const curEnv: TFaCursorEnviron
  ): boolean;
{Verifica si el patrón indicado, cumple con las condiciones actuales (after)}
begin
  case nAft of
  0: begin  //no hay elementos, siempre cumple
    exit(true);
  end;
  1: begin  //hay elem[0]
      //es independiente de "inMidTok"
      Result := MatchPatternElement(0, curEnv.tok0, curEnv.caseSen);
    end;
  end;
end;
function TFaOpenEvent.MatchPattern(const curEnv: TFaCursorEnviron): boolean;
  function ItemInBlock: boolean;  inline;
  begin
    Result := (block = nil) or //es válido para todos los bloques
              (block = curEnv.curBlock);
  end;
begin
  Result := MatchPatternBefore(curEnv) and
            MatchPatternAfter(curEnv) and ItemInBlock;
  {$IFDEF Verbose}
  if Result then debugln(' -> Aplicable Pat:'+ name);
  {$ENDIF}
end;
procedure TFaOpenEvent.AddItem(txt: string);
{Agrega un ítem al evento de apertura. Versión simplificada}
var
  n: Integer;
begin
  n := high(Items)+1;  //tamaño de matriz
  setlength(Items, n+1);
  ExtractCompletItem(txt, Items[n]);
end;
procedure TFaOpenEvent.AddItems(lst: TStringList; blk: TFaSynBlock);
{Agrega una lista de ítems al evento de apertura, desde un  TStringList}
var
  n: Integer;
  r : TFaCompletItem;
  i: Integer;
begin
  n := high(Items)+1;  //tamaño de matriz
  setlength(Items, n+lst.Count);
  for i:= 0 to lst.Count-1 do begin
    ExtractCompletItem(lst[i], Items[n+i]);
  end;
end;
procedure TFaOpenEvent.AddItems(const lItems: TFaCompletItems);
{Agrega una lista de ítems desde un arreglo TFaCompletItems}
var
  n: Integer;
  r : TFaCompletItem;
  i: Integer;
begin
  n := high(Items)+1;  //tamaño de matriz
  setlength(Items, n+high(lItems)+1);
  for i:= 0 to High(lItems) do begin
    r.text    :=lItems[i].text;
    r.content :=lItems[i].content;
    r.descrip :=lItems[i].descrip;
    r.OffCur  :=lItems[i].OffCur;
    Items[n+i] := r;
  end;
end;
procedure TFaOpenEvent.AddItems(list: string; blk: TFaSynBlock);
{Agrega una lista de ítems al evento de apertura, desde una cadena }
var
  lst: TStringList;
begin
  lst := TStringList.Create;
  //troza
  lst.Delimiter := ' ';
  lst.DelimitedText := list;
  //agrega
  AddItems(lst, blk);
  lst.Destroy;
end;
procedure TFaOpenEvent.ClearItems;
begin
  setlength(Items, 0);
end;
constructor TFaOpenEvent.Create(hlt0: TSynFacilSyn);
begin
  hlt := hlt0;
end;

{ TSynCompletionF }
function TSynCompletionF.OnSynCompletionPaintItem(const AKey: string;
  ACanvas: TCanvas; X, Y: integer; IsSelected: boolean; Index: integer): boolean;
var
  MaxX: Integer;
  hl: TSynCustomHighlighter;
begin
  //configura propiedades de texto
//  if (Editor<>nil) then begin
//    ACanvas.Font := Editor.Font
//  end;
  ACanvas.Font.Style:=[];
{  if not IsSelected then
    ACanvas.Font.Color := FActiveEditDefaultFGColor
  else
    ACanvas.Font.Color := FActiveEditSelectedFGColor;}
  MaxX:=TheForm.ClientWidth;
  hl := nil;
  if Editor <> nil then
    hl := Editor.Highlighter;
  PaintCompletionItem(AKey, ACanvas, X, Y, MaxX, IsSelected, Index, self);

  Result := false;
//  Result:=true;  //para indicar que lo intercepta
end;
function TSynCompletionF.PaintCompletionItem(const AKey: string;
  ACanvas: TCanvas; X, Y, MaxX: integer; ItemSelected: boolean; Index: integer;
  aCompletion: TSynCompletion): TPoint;

var
  BGRed: Integer;
  BGGreen: Integer;
  BGBlue: Integer;
  TokenStart: Integer;
  BackgroundColor: TColorRef;
  ForegroundColor: TColorRef;

  procedure SetFontColor(NewColor: TColor);
  var
    FGRed: Integer;
    FGGreen: Integer;
    FGBlue: Integer;
    RedDiff: integer;
    GreenDiff: integer;
    BlueDiff: integer;
  begin
    NewColor := TColor(ColorToRGB(NewColor));
    FGRed:=(NewColor shr 16) and $ff;
    FGGreen:=(NewColor shr 8) and $ff;
    FGBlue:=NewColor and $ff;
    RedDiff:=Abs(FGRed-BGRed);
    GreenDiff:=Abs(FGGreen-BGGreen);
    BlueDiff:=Abs(FGBlue -BGBlue);
    if RedDiff*RedDiff + GreenDiff*GreenDiff + BlueDiff*BlueDiff<30000 then
    begin
      NewColor:=InvertColor(NewColor);
      {IncreaseDiff(FGRed,BGRed);
      IncreaseDiff(FGGreen,BGGreen);
      IncreaseDiff(FGBlue,BGBlue);
      NewColor:=(FGRed shl 16) or (FGGreen shl 8) or FGBlue;}
    end;
    ACanvas.Font.Color:=NewColor;
  end;

  procedure WriteToken(var TokenStart, TokenEnd: integer);
  var
    CurToken: String;
  begin
    if TokenStart>=1 then begin
      CurToken:=copy(AKey,TokenStart,TokenEnd-TokenStart);
      ACanvas.TextOut(x+1, y, CurToken);
      x := x + ACanvas.TextWidth(CurToken);
      //debugln('Paint A Text="',CurToken,'" x=',dbgs(x),' y=',dbgs(y),' "',ACanvas.Font.Name,'" ',dbgs(ACanvas.Font.Height),' ',dbgs(ACanvas.TextWidth(CurToken)));
      TokenStart:=0;
    end;
  end;

var
  s: string;
//  IdentItem: TIdentifierListItem;
  AColor: TColor;
  IsReadOnly: boolean;
  ImageIndex: longint;
begin
  ForegroundColor := ColorToRGB(ACanvas.Font.Color);
  Result.X := 0;
  Result.Y := ACanvas.TextHeight('W');


  // draw
    BackgroundColor:=ColorToRGB(ACanvas.Brush.Color);
    BGRed:=(BackgroundColor shr 16) and $ff;
    BGGreen:=(BackgroundColor shr 8) and $ff;
    BGBlue:=BackgroundColor and $ff;
    ImageIndex:=-1;


        AColor:=clBlack;
        s:='keyword';


    SetFontColor(AColor);
    ACanvas.TextOut(x+1,y,s);
    inc(x,ACanvas.TextWidth('constructor '));
    if x>MaxX then exit;

    // paint the identifier
    SetFontColor(ForegroundColor);
    ACanvas.Font.Style:=ACanvas.Font.Style+[fsBold];
    s:='identificador';
    //DebugLn(['PaintCompletionItem ',x,',',y,' ',s]);
    ACanvas.TextOut(x+1,y,s);
    inc(x,ACanvas.TextWidth(s));
    if x>MaxX then exit;
    ACanvas.Font.Style:=ACanvas.Font.Style-[fsBold];

    ImageIndex := -1;

    // paint icon
    if ImageIndex>=0 then begin
      //IDEImages.Images_16, es de tipo TCustomImageList
//      IDEImages.Images_16.Draw(ACanvas,x+1,y+(Result.Y-16) div 2,ImageIndex);
      inc(x,18);
      if x>MaxX then exit;
    end;

end;
procedure TSynCompletionF.Refresh;
begin
  if ItemList.Count = 0 then begin
    //cierra por no tener elementos
    Deactivate;
  end else begin
    //hay elementos
    Position:=0;  //selecciona el primero
  end;
  TheForm.Invalidate;  //para que se actualice
end;
constructor TSynCompletionF.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  //intercepta este evento
//  OnPaintItem:=@OnSynCompletionPaintItem;
end;

{ TSynFacilComplet }
procedure TSynFacilComplet.ReadSpecialIdentif;
//Hace una exploración para leer todos los identificadores especiales en la tabla
//SpecIdentifiers[].
var
  met: TFaProcMetTable;
  p: TPtrATokEspec;
  c: Char;
  i: Integer;
  n: Integer;
begin
  setlength(SpecIdentifiers,0);
  if CaseSensitive then begin
    for c in ['A'..'Z','a'..'z'] do begin
      TableIdent(c, p, met);
      if p<> nil then begin
        for i:= 0 to high(p^) do begin
          n := high(SpecIdentifiers)+1;  //tamaño de matriz
          setlength(SpecIdentifiers,n+1);
          SpecIdentifiers[n] := p^[i];
        end;
      end;
    end;
  end else begin  //no es sensible a la caja
    for c in ['A'..'Z'] do begin
      TableIdent(c, p, met);
      if p<> nil then begin
        for i:= 0 to high(p^) do begin
          n := high(SpecIdentifiers)+1;  //tamaño de matriz
          setlength(SpecIdentifiers,n+1);
          SpecIdentifiers[n] := p^[i];
        end;
      end;
    end;
  end;
end;
function TSynFacilComplet.LoadSyntaxFromPath(SourceFile: string; path: string;
              CaseSens: boolean = false): string;
//Carga un archivo de sintaxis, buscando el resaltador apropiado en un directorio.
//Si encuentra el archivo de sintaxis apropiado, devuelve el nombre del archivo usado
//(sin incluir la ruta), de otra forma, devuelve una cadena vacía.
var
  ext: String;
  Hay: Boolean;
  SR : TSearchRec;
  rut: String;
begin
  Result := '';
  ext := ExtractFileExt(SourceFile);
  if ext<>'' then ext := copy(ext, 2, 10);  //quita el punto
  //explora los lenguajes para encontrar alguno que soporte la extensión dada
  Hay := FindFirst(path + '\*.xml',faAnyFile - faDirectory, SR) = 0;
  while Hay do begin
     //encontró archivo, lee sus extensiones
     rut := path + '\' + SR.name;
     if XMLFileHaveExten(rut, ext, CaseSens) then  begin //encontró
       LoadFromFile(rut);  //carga sintaxis
       Result := SR.name;
       exit;
     end;
     //no encontró extensión, busca siguiente archivo
     Hay := FindNext(SR) = 0;
  end;
  //no encontró
end;
procedure TSynFacilComplet.ProcXMLOpenOn(nodo: TDOMNode);
{Procesa el bloque <OpenOn ... >}
var
  listIden: string;
  tNamPatt, tBefPatt, tAftPatt: TFaXMLatrib;
  filt: TFaFilterList;
  tFilPatt, tBlkPatt: TFaXMLatrib;
  oPat: TFaOpenEvent;
  blk: TFaSynBlock;
  success: boolean;
  tActPatt: TFaXMLatrib;
  tIncAttr, tIncList: TFaXMLatrib;
  tipTok: TSynHighlighterAttributes;
  i,j : Integer;
  nodo2: TDOMNode;
  lst: TFaCompletionList;
begin
  tNamPatt := ReadXMLParam(nodo,'Name');
  tBefPatt := ReadXMLParam(nodo,'BeforePattern');
  tAftPatt := ReadXMLParam(nodo,'AfterPattern');
  tFilPatt := ReadXMLParam(nodo,'FilterBy');
  tBlkPatt := ReadXMLParam(nodo,'Block');
  tActPatt := ReadXMLParam(nodo,'Action');
  CheckXMLParams(nodo, 'Name BeforePattern AfterPattern FilterBy Block Action');  //puede generar excepción
  if tFilPatt.hay then begin
    case UpCase(tFilPatt.val) of
    'NONE'         : filt := fil_None;
    'LASTTOK'      : filt := fil_LastTok;
    'LASTTOKPART'  : filt := fil_LastTokPart;
    'LASTIDENT'    : filt := fil_LastIdent;
    'LASTIDENTPART': filt := fil_LastIdentPart;
    else
      raise ESynFacilSyn.Create(Format(ERR_FILTER_NO_EXIST,[tFilPatt.val]));
    end;
  end else begin
    filt := fil_LastTokPart;   //valro por defecto
  end;
  if not tAftPatt.hay then begin
    tAftPatt.val:='Identifier';
  end;
  //agrega patrón
  oPat := AddOpenEvent(tAftPatt.val, tBefPatt.val, filt);
  //configrua nombre
  if tNamPatt.hay then begin  //se especificó nombre
    oPat.name := tNamPatt.val;
  end else begin  //se asuem un ombre por defecto
    oPat.name := '#Pat' + IntToStr(OpenPatterns.Count);
  end;
  //configura bloque
  if tBlkPatt.hay then begin
    blk := SearchBlock(tBlkPatt.val, success);
    if not success then begin
      raise ESynFacilSyn.Create(ERR_INVAL_BLK_NAME);
    end;
    oPat.block := blk;
  end else begin
    oPat.block := nil;
  end;
  //configura acción
  if tActPatt.hay then begin
    case UpCAse(tActPatt.val) of
    'NONE'   : oPat.Action := pac_None;
    'DEFAULT': oPat.Action := pac_Default;
    'INSERT' : oPat.Action := pac_Insert;
    'REPLASTTOK': oPat.Action := pac_Rep_LastTok;
    else
      raise ESynFacilSyn.Create(Format(ERR_ACTION_NO_EXIST,[tActPatt.val]));
    end;
  end else begin
    oPat.Action := pac_Default;
  end;
  //verifica contenido
  listIden := nodo.TextContent;
  if listIden<>'' then begin
    //Se ha especificado lista de palabras. Los carga
    oPat.AddItems(listIden, nil);
  end;
  //explora nodos
  for i := 0 to nodo.ChildNodes.Count-1 do begin
    nodo2 := nodo.ChildNodes[i];
    if UpCAse(nodo2.NodeName)='INCLUDE' then begin  //incluye lista de palabras por atributo
      //lee parámetros
      tIncAttr := ReadXMLParam(nodo2,'Attribute');
      tIncList := ReadXMLParam(nodo2,'List');
      CheckXMLParams(nodo2, 'Attribute List');  //puede generar excepción
      if tIncAttr.hay then begin
        //se pide agregar la lista de identificadores de un atributo en especial
        if IsAttributeName(tIncAttr.val)  then begin
          tipTok := GetAttribByName(tIncAttr.val);   //tipo de atributo
          //busca los identificadores para agregarlos
          for j:= 0 to high(SpecIdentifiers) do begin
            if SpecIdentifiers[j].tTok = tipTok then begin
              oPat.AddItem(SpecIdentifiers[j].orig); {Agrega a lista por defecto.}
            end;
          end;
        end else begin  //atributo no existe
          raise ESynFacilSyn.Create(Format(ERR_ATTRIB_NO_EXIST,[nodo2.NodeValue]));
        end;
      end;
      if tIncList.hay then begin
        //se pide agreagr los ítems de una lista
        lst := GetListByName(tIncList.val);
        if lst<>nil then begin
          oPat.AddItems(lst.Items);
        end else begin

        end;
      end;
    end else if nodo2.NodeName='#text' then begin
      //éste nodo aparece siempre que haya espacios, saltos o tabulaciones
    end else if LowerCase(nodo2.NodeName) = '#comment' then begin
      //solo para evitar que de mensaje de error
    end else begin
      raise ESynFacilSyn.Create(Format(ERR_INVAL_LAB_OPNON,[nodo2.NodeName]));
    end;
  end;
end;
procedure TSynFacilComplet.ProcCompletionLabel(nodo: TDOMNode);
//Procesa la etiqueta <Completion>, que es el bloque que define todo el sistema de
//completado de código.
var
  listIden: string;
  i,j   : Integer;
  nodo2: TDOMNode;
  tipTok: TSynHighlighterAttributes;
  hayOpen: Boolean;
  tIncAttr: TFaXMLatrib;
  tLstName: TFaXMLatrib;
  defPat: TFaOpenEvent;
  cmpList: TFaCompletionList;
begin
  hayOpen := false;  //inicia bandera
  //crea evento de apertura por defecto
  defPat := AddOpenEvent('Identifier', '', fil_LastTokPart);
  defpat.name:='#Def';
  ////////// explora nodos hijos //////////
  for i := 0 to nodo.ChildNodes.Count-1 do begin
    nodo2 := nodo.ChildNodes[i];
    if UpCAse(nodo2.NodeName)='INCLUDE' then begin  //incluye lista de palabras por atributo
      //lee parámetros
      tIncAttr := ReadXMLParam(nodo2,'Attribute');
      CheckXMLParams(nodo2, 'Attribute');  //puede generar excepción
      if tIncAttr.hay then begin
        //se pide agregar la lista de identificadores de un atributo en especial
        if IsAttributeName(tIncAttr.val)  then begin
          tipTok := GetAttribByName(tIncAttr.val);   //tipo de atributo
          //busca los identificadores para agregarlos
          for j:= 0 to high(SpecIdentifiers) do begin
            if SpecIdentifiers[j].tTok = tipTok then begin
              defPat.AddItem(SpecIdentifiers[j].orig); {Agrega a lista por defecto.}
            end;
          end;
        end else begin  //atributo no existe
          raise ESynFacilSyn.Create(Format(ERR_ATTRIB_NO_EXIST,[nodo2.NodeValue]));
        end;
      end;
    end else if UpCAse(nodo2.NodeName)='OPENON' then begin  //evento de apertura
      //lee parámetros
      hayOpen :=true;   //marca para indicar que hay lista
      ProcXMLOpenOn(nodo2);  //puede generar excepción.
    end else if UpCAse(nodo2.NodeName)='LIST' then begin  //forma alternativa para lista de palabras
      //Esta forma de declaración permite definir un orden en la carga de listas
      //lee parámetros
      tLstName :=  ReadXMLParam(nodo2,'Name');
      CheckXMLParams(nodo2, 'Name');  //puede generar excepción
      if not tLstName.hay then begin
        tLstName.val:='#list'+IntToStr(CompletLists.Count);
      end;
      cmpList := AddComplList(tLstName.val);
      //Ve si tiene contenido
      listIden := nodo2.TextContent;
      if listIden<>'' then begin
        cmpList.AddItems(listIden);
        {Agrega los ítems de la lista en este patrón, por si se llegase a utilizar. Se
        hace aquí mismo para mantener el orden, si es que se mezcla con etiquetas <INCLUDE>
        o listas de palabras indicadas directamente en <COMPLETION> ... </COMPLETION>}
        defPat.AddItems(listIden, nil);
      end;
    end else if nodo2.NodeName='#text' then begin
      //éste nodo aparece siempre que haya espacios, saltos o tabulaciones
//      debugln('#text:'+nodo2.NodeValue);
      defPat.AddItems(nodo2.NodeValue, nil);
    end else if LowerCase(nodo2.NodeName) = '#comment' then begin
      //solo para evitar que de mensaje de error
    end else begin
      raise ESynFacilSyn.Create(Format(ERR_INVAL_LAB_COMP,[nodo2.NodeName]));
    end;
  end;
  //verifica las opciones por defecto
  if hayOpen then begin
    //Se ha especificado patrones de apretura.
    OpenPatterns.Remove(defPat);  //elimina el evento por defecto, porque no se va a usar
  end else begin
    //No se ha especificado ningún evento de apertura
    //mantiene el evento por defecto
  end;
end;
procedure TSynFacilComplet.LoadFromFile(Arc: string);
var
  doc: TXMLDocument;
  i: Integer;
  nodo: TDOMNode;
  nombre: WideString;
  tCasSen: TFaXMLatrib;
  tOpenKUp: TFaXMLatrib;
  tSelOEnt: TFaXMLatrib;
begin
  inherited LoadFromFile(Arc);  {Puede disparar excepción. El mesnajes de error generado
                                incluye el nombre del archivo}
  OpenOnKeyUp := true;     //por defecto
  ReadSpecialIdentif;      //carga los identificadores especiales
  OpenPatterns.Clear;      //limpia patrones de apertura
  CompletLists.Clear;
  try
    ReadXMLFile(doc, Arc);  //carga archivo
    //procede a la carga de la etiqueta <COMPLETION>
    for i:= 0 to doc.DocumentElement.ChildNodes.Count - 1 do begin
       // Lee un Nodo o Registro
       nodo := doc.DocumentElement.ChildNodes[i];
       nombre := UpCase(nodo.NodeName);
       if nombre = 'COMPLETION' then  begin
         //carga los parámetros
         tCasSen :=ReadXMLParam(nodo, 'CaseSensitive');
         tOpenKUp:=ReadXMLParam(nodo, 'OpenOnKeyUp');
         tSelOEnt:=ReadXMLParam(nodo, 'SelectOnEnter');
         //carga atributos leidos
         if tCasSen.hay then  //si se especifica
           CaseSensComp := tCasSen.bol  //se lee
         else  //si no
           CaseSensComp := CaseSensitive;  //toma el del resaltador
         if tOpenKUp.hay then OpenOnKeyUp:=tOpenKUp.bol;
         if tSelOEnt.hay then SelectOnEnter:=tSelOEnt.bol;
         ProcCompletionLabel(nodo);  //Puede generar error
       end;
    end;
    doc.Free;  //libera
  except
    on e: Exception do begin
      //Completa el mensaje con nombre de archivo, porque esta parte del código
      //no lo incluye.
      e.Message:=ERROR_LOADING_ + Arc + #13#10 + e.Message;
      doc.Free;
      raise   //genera de nuevo
    end;
  end;
end;
procedure TSynFacilComplet.SelectEditor(ed0: TSynEdit);
//Inicia el motor de ayuda contextual, en el editor indicado
begin
  ed := ed0;    //guarda referencia
  if ed = nil then begin
    showmessage('ERROR: Se requiere un editor para el autocompletado.');
    ed := nil;   //para indicar que no es válido
    exit;
  end;
  //asigna por si acaso no se había hecho
  ed.Highlighter :=  self;
  MenuComplet:=TSynCompletionF.Create(ed.Owner);   //crea menú contextual en el formulario
  MenuComplet.Editor:=ed;     //asigna editor
  MenuComplet.Width:=200;     //ancho inicial
  MenuComplet.OnExecute:=@OnExecute;
  MenuComplet.OnCodeCompletion:=@OnCodeCompletion;
  //iintercepta eventos de teclado, para cambiar comportamiento
  MenuComplet.OnKeyDown:=@FormKeyDown;
  MenuComplet.OnUTF8KeyPress:=@FormUTF8KeyPress;  //eventos del teclado de la ventana de completado
end;
procedure TSynFacilComplet.UnSelectEditor;
//Método que quita la ayuda contextual al formulario indicado y al editor.
//Se debería llamar siempre si se ha llamado a SelectEditor().
begin
  if MenuComplet = nil then exit;  //nunca se creó
  MenuComplet.Destroy;
  MenuComplet := nil;  //lo marca como  liberado
end;
function TSynFacilComplet.CheckForClose: boolean;
{Verifica si se dan las condiciones como para cerrar la ventana de completado, y si se da
el caso, la cierra y devuelve TRUE.}
var
  opEve: TFaOpenEvent;
begin
  curEnv.LookAround(ed, CaseSensComp);  //para actualizar el nuevo estado
  opEve := FindOpenEventMatching;    //Busca evento de apertura que aplica
  if opEve = nil then begin
    MenuComplet.Deactivate;
    CurOpenPat := nil;  //como se cierra ya no hay evento activo
    exit(true);  //ninguno aplica
  end;
  //hay un aptrón que aplica
  if opEve=CurOpenPat then begin
    //Es el mismo
    exit(false);
  end else begin
    //Es uno nuevo
    {Aquí se puede decidir cerrar la ventana, porque aplica otro patrón, pero yo prefiero
     el comportamiento en el que se aplica direcatamente el nuevo patrón, sin necesidad de
     esperar a pulsar otra tecla.}
    CurOpenPat := opEve;   //actualiza referencia
    CurOpenPat.LoadItems(curEnv);  //carga ítems
    exit(false);
  end;
end;

function TSynFacilComplet.AddOpenEvent(AfterPattern, BeforePattern: string;
  filter: TFaFilterList): TFaOpenEvent;
{Permite agregar un evento de apertura. Devuelve una referencia al evento agregado.}
  procedure AddElement(strElem: string; var patEle: TFaPatternElement; var success: boolean);
  {Agrega un elemento a un registro TFaOpenEvent, de acuerdo a su contenido.}
  begin
    success := true;
    if strElem[1] in WORD_CHARS then begin
      //es una palabra
      if strElem[1] = '!' then begin
        //debe ser de tipo "No es ..."
        strElem := copy(strElem,2,length(strElem)); //quita caracter
        if upcase(strElem) = upcase(ALL_IDENTIF) then begin
           //es de tipo "Todos los identificadores"
           patEle.patKind := pak_NoIdentif;
        end else if IsAttributeName(strElem) then begin
           //Es nombre de tipo de token
           patEle.patKind := pak_NoTokTyp;
           patEle.toktyp := GetAttribByName(strElem);   //tipo de atributo
        end else begin  //no es, debe haber algún error
           success := false;
           exit;
        end;
      end else if upcase(strElem) = upcase(ALL_IDENTIF) then begin
        //es de tipo "Todos los identificadores"
        patEle.patKind := pak_Identif;
      end else if IsAttributeName(strElem) then begin  //es
        //Es nombre de tipo de token
        patEle.patKind := pak_TokTyp;
        patEle.toktyp := GetAttribByName(strElem);   //tipo de atributo
      end else begin  //no es, debe haber algún error
        success := false;
        exit;
      end;
    end else if strElem[1] in STR_DELIM then begin
      //es una cadena delimitada
      if strElem[length(strElem)] <> strElem[1] then begin  //verificación
        success := false;
        exit;
      end;
      patEle.patKind := pak_String;
      patEle.str:= copy(strElem, 2, length(strElem)-2);
    end else begin
      success := false;
    end;
  end;
var
  opEve: TFaOpenEvent;
  elem : String;
  nelem: Integer;
  success: boolean;
  i: Integer;
begin
  opEve := TFaOpenEvent.Create(self);
  ///////analiza AfterPattern
  AfterPattern := trim(AfterPattern);
  if AfterPattern='' then begin
    //no se especifica
    opEve.elem[-3].patKind := pak_none;
    opEve.elem[-2].patKind := pak_none;
    opEve.elem[-1].patKind := pak_none;
    opEve.nBef:=0;  //no hay elementos válidos
  end else begin
    //Caso común
    //extrae y guarda los elementos
    elem := opEve.ExtractElem(AfterPattern);
    nelem := 0;  //contedor
    while (elem<>'#') and (elem<>'') and (nelem<=3) do begin
      AddElement(elem, opEve.elem[nelem-3], success);
      if not success then begin
        opEve.Destroy;  //no lo agregó
        raise ESynFacilSyn.Create(ERR_PAR_BEF_PATT);
      end;
      elem := opEve.ExtractElem(AfterPattern);
      inc(nelem);
    end;
    //verifica
    if elem = '#' then begin
      opEve.Destroy;  //no lo agregó
      raise ESynFacilSyn.Create(ERR_PAR_BEF_PATT);
    end;
    if nelem>3 then begin
      opEve.Destroy;  //no lo agregó
      raise ESynFacilSyn.Create(ERR_PAR_BEF_PATT);
    end;
    //alinea elementos encontrados
    opEve.nBef:=3;   //valor asumido, se ajustará al valor real
    for i:=1 to 3-nelem do begin
      opEve.ShiftPatterns;
    end;
  end;
  ///////analiza BeforePattern
  BeforePattern := trim(BeforePattern);
  if BeforePattern='' then begin
    //no se especifica
    opEve.elem[0].patKind := pak_none;
    opEve.nAft:=0;  //no hay
  end else begin
    //hay un patrón después
    elem := opEve.ExtractElem(BeforePattern);
    if elem = '#' then begin
      opEve.Destroy;  //no lo agregó
      raise ESynFacilSyn.Create(ERR_PAR_AFT_PATT);
    end;
    if BeforePattern<>'' then begin  //no deberái quedar nada
      opEve.Destroy;  //no lo agregó
      raise ESynFacilSyn.Create(ERR_PAR_AFT_PATT);
    end;
    AddElement(elem, opEve.elem[0], success);
    if not success then begin
      opEve.Destroy;  //no lo agregó
      raise ESynFacilSyn.Create(ERR_PAR_AFT_PATT);
    end;
    opEve.nAft:=1;  //hay uno
  end;
  setlength(opEve.Items, 0);  //inicia tabla de ítems
  //Hay propiedades que no se inician aquí como el nombre
  opEve.filter := filter;     //fija filtro
  opEve.block := nil;
  opEve.Action := pac_Default;  //acción por defecto
  OpenPatterns.Add(opEve);   //agrega
  Result := opEve;  //devuelve referencia
end;
function TSynFacilComplet.AddComplList(lstName: string): TFaCompletionList;
var
  lst: TFaCompletionList;
begin
  lst := TFaCompletionList.Create;
  lst.Name:= lstName;
  CompletLists.Add(lst);
  Result := lst;
end;
function TSynFacilComplet.GetListByName(lstName: string): TFaCompletionList;
{Devuelve la referencia a una lista, usando su nombre. Si no enecuentra devuelve NIL}
var
  l: TFaCompletionList;
  UlstName: String;
begin
  UlstName := upcase(lstName);
  for l in CompletLists do begin
    if Upcase(l.Name) = UlstName then
      exit(l);
  end;
  exit(nil);
end;
procedure TSynFacilComplet.OnCodeCompletion(var Value: string;
  SourceValue: string; var SourceStart, SourceEnd: TPoint; KeyChar: TUTF8Char;
  Shift: TShiftState);
//Se genera antes de hacer el reemplazo del texto. "Value", es la cadena que se usará
//para reemplazar la palabra en el editor.
begin
  //Se puede usar "MenuComplet.Position" para saber el elemento seleccionado de la lista
//  value := 'hola';
//  showmessage(value);
end;
function TSynFacilComplet.FindOpenEventMatching: TFaOpenEvent;
{Devuelve el priumer evento que coincide con el entorno actual "curEnv". Si ninguno coincide,
devuelve NIL.}
var
  opEve: TFaOpenEvent;
begin
  for opEve in OpenPatterns do begin
    if opEve.MatchPattern(curEnv) then begin
      Result := opEve;   //devuelve referencia
      exit;
    end;
  end;
  exit(nil);   //no enccontró
end;
procedure TSynFacilComplet.OnExecute(Sender: TObject);
//Este evento se genera antes de abrir el menú de completado.
//Llena la lista "AvailItems", con los ítems que correspondan de acuerdo a la posición
//actual del cursor y de la configuración del archivo XML.
//Luego llena el menú contextual con los ítems filtrados de acuerdo a la posición actual.
var
  opEve: TFaOpenEvent;
begin
  MenuComplet.ItemList.Clear;   //inicia menú
  //Verifica si se va a abrir la lista por tecla común. La otra opción es por un atajo
  if MenuComplet.CurrentString='<KeyUp>' then begin
//    debugln('OnExecute: Abierto por tecla común utKey='+utKey+',vKey='+IntToStr(vKey));
    if (vKey in [VK_BACK, VK_TAB] ) and (vShift=[]) then begin
      //esta tecla es válida
    end else if (utKey<>'') and (utKey[1] in [#8,#9,' '..'/','A'..'Z','a'..'z']) then begin
      //esta tecla es válida
    end else begin
      //los otros casos no se consideran que deban explorarse
      exit;
    end;
  end;
  //Prepara para llenar la lista de completado
  curEnv.LookAround(ed, CaseSensComp);  //Lee entorno.
  CurOpenPat := nil;
  opEve := FindOpenEventMatching;    //Busca evento de apertura que aplica
  if opEve<>nil then begin
    //Se cumple el evento en la posición actual del cursor
    opEve.LoadItems(curEnv);   //carga los ítems con los que trabajará.
    CurOpenPat := opEve;   //guarda referencia
  end;
  FillCompletMenuFiltered;  //hace el primer filtrado

//Después de llenar la lista, se puede ver si tiene o no elementos
  if MenuComplet.ItemList.Count <> 0 then begin  //se abrirá
    if MenuComplet.ItemList.Count  = 1 then begin
      //se agrega un elemento más porque sino SynCompletion, hará el reemplazo automáticamente.
      MenuComplet.ItemList.Add('');
    end;
  end;
end;
procedure TSynFacilComplet.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
  procedure SeleccionarPalabra;
  {Selecciona, la palabra actual de la lista de completado. Usamos nuestra propia
  rutina en vez de OnValidate(), para poder reemplazar identificadores de acuerdo
  a la definición de sintaxis, además de otros tipos de tokens.}
  var
    NewWord: String;
  begin
    if CurrentLines = nil then exit;
    //Reemplaza actual
    NewWord := MenuComplet.ItemList[MenuComplet.Position];
    CurOpenPat.DoAction(ed, curEnv, NewWord);   //realiza la acción programada
    CloseCompletionWindow;  //cierra
  end;
begin
//debugln('Form.OnKeyDown:'+ XXX +':'+IntToStr(ed.CaretX));
  case Key of
    VK_RETURN: begin
        if Shift= [] then begin
           if SelectOnEnter then  //solo si está permitido reemplazar
             SeleccionarPalabra;
           Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
        end else begin
          Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
          CloseCompletionWindow;  //cierra
        end;
      end;
    VK_HOME: begin
        if Shift = [] then begin  //envía al editor
           ed.CommandProcessor(ecLineStart, #0, nil);
           MenuComplet.Deactivate;  //desactiva
        end else if Shift = [ssShift] then begin
          ed.CommandProcessor(ecSelLineStart, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end;
        Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
      end;
    VK_END: begin
        if Shift = [] then begin  //envía al editor
           ed.CommandProcessor(ecLineEnd, #0, nil);
           MenuComplet.Deactivate;  //desactiva
        end else if Shift = [ssShift] then begin
          ed.CommandProcessor(ecSelLineEnd, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end;
        Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
      end;
    VK_BACK: begin
        if Shift = [] then begin  //sin Ctrl o Shift
          ed.CommandProcessor(ecDeleteLastChar, #0, nil);  //envía al editor
          if CheckForClose then begin Key:=VK_UNKNOWN; exit end;
          FillCompletMenuFiltered;
        end;
        Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
      end;
    VK_DELETE: begin
        if Shift = [] then begin  //sin Ctrl o Shift
          ed.CommandProcessor(ecDeleteChar, #0, nil);  //envía al editor
          if CheckForClose then begin Key:=VK_UNKNOWN; exit end;
          FillCompletMenuFiltered;
        end;
        Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
      end;
    VK_LEFT: begin
        if Shift = [] then begin  //envía al editor
          ed.CommandProcessor(ecLeft, #0, nil);
          if CheckForClose then begin Key:=VK_UNKNOWN; exit end;
          FillCompletMenuFiltered;
        end else if Shift = [ssShift] then begin
          ed.CommandProcessor(ecSelLeft, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end else if Shift = [ssCtrl] then begin
          ed.CommandProcessor(ecWordLeft, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end else if Shift = [ssShift,ssCtrl] then begin
          ed.CommandProcessor(ecSelWordLeft, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end;
        Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
      end;
    VK_RIGHT: begin
        if Shift = [] then begin  //envía al editor
          ed.CommandProcessor(ecRight, #0, nil);
          if CheckForClose then begin Key:=VK_UNKNOWN; exit end;
          FillCompletMenuFiltered;
        end else if Shift = [ssShift] then begin
          ed.CommandProcessor(ecSelRight, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end else if Shift = [ssCtrl] then begin
          ed.CommandProcessor(ecWordRight, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end else if Shift = [ssShift,ssCtrl] then begin
          ed.CommandProcessor(ecSelWordRight, #0, nil);
          MenuComplet.Deactivate;  //desactiva
        end;
        Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
      end;
    VK_TAB: begin
        if Shift = [] then begin
          SeleccionarPalabra;
          SearchOnKeyUp := false;  {para que no intente buscar luego en el evento KeyUp,
                   porque TAB está configurado como tecla válida para abrir la lista, y si
                   se abre, (y no se ha isertado el TAB), aparecerá de nuevo el mismo
                   identificador en la lista}
          Key:=VK_UNKNOWN;   //marca para que no lo procese SynCompletion
        end;
      end;
  end;
  //si no lo procesó aquí, lo procesará SynCompletion
end;
procedure TSynFacilComplet.FormUTF8KeyPress(Sender: TObject;
  var UTF8Key: TUTF8Char);
//Este evento se dispara cuando ya está visible la ventana de autocompletado y por
//lo tanto no se generará el evento KeyUp
begin
  //Como este evento se genera apneas pulsar una tecla, primero pasamos la tecla al
  //editor para que lo procese y así tendremos el texto modificado, como si estuviéramos
  //después de un KeyUp().
  ed.CommandProcessor(ecChar, UTF8Key, nil);
  UTF8Key := '';  //limpiamos para que ya no lo procese SynCompletion
  //ahora ya tenemos al editor cambiado
  //Las posibles opciones ya se deben haber llenado. Aquí solo filtramos.
  if CheckForClose then exit;
  FillCompletMenuFiltered;
end;
procedure TSynFacilComplet.UTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
{Debe recibir la tecla pulsada aquí, y guardarla para KeyUp, porque allí no se puede
reconocer caracteres ASCII. Se usa UTF para hacerlo más fléxible}
begin
  utKey:=UTF8Key;  //guarda tecla
end;
procedure TSynFacilComplet.KeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
{Verifica la tecla pulsada, para determinar si abrir o no el menú de ayuda contextual
 Debe llamarse después de que el editor ha procesado el evento, para tener
 el estado final del editor
 Este evento solo se ejecutará una vez antes de abrir la ventana de autocompletado}
begin
  {$IFDEF Verbose}
  debugln('--KeyUp:' + IntToStr(key));
  {$ENDIF}
  if not CompletionOn then exit;
  if not OpenOnKeyUp then exit;
  if not SearchOnKeyUp then begin
    //Se ha inhabilitado este evento para el completado
    SearchOnKeyUp := true;
    exit;
  end;
  //verificación principal
  if MenuComplet.IsActive then begin
    //verifica si debe desaparecer la ventana, por mover el cursor a una posición anterior
//    if CompareCarets(Pos0, CurrentEditor.CaretXY) < 0 then
//      Deactivate;
    exit;   //ya está mostrado
  end;
  if ed = NIL then exit;     //no hay editor
  if ed.SelectionMode <> smNormal then exit;  //para no interferir en modo columna
  //captura las teclas pulsadas y llama a OnExecute(), para ver si correspodne mostrar
  //la ventana de completado
  vKey := Key;   //guarda
  vShift := Shift;
  //Dispara evento OnExecute con el valor de "vKey", "vShift" y "utKey" actualizados
  OpenCompletionWindow;  //solo se mostrará si hay ítems
  vKey := 0;
  vShift := [];  //limpia
  utKey := '';  //limpia por si la siguiente tecla pulsada no dispara a UTF8KeyPress()
  SearchOnKeyUp := true;  //limpia bandera
End;
procedure TSynFacilComplet.FillCompletMenuFiltered;
//Llena el menú de completado a partir de "AvailItems", filtrando solo las
//palabras que coincidan con "str"
begin
  //Genera la lista que coincide
  { Este proceso puede ser lento si se actualizan muchas opciones en la lista }
  MenuComplet.ItemList.Clear;  {Limpia todo aquí porque este método es llamado desde distintos
                                puntos del programa.}
  if CurOpenPat <> nil then begin
    CurOpenPat.FillFilteredIn(curEnv, MenuComplet.ItemList);
  end;
  MenuComplet.Refresh;
end;
procedure TSynFacilComplet.OpenCompletionWindow;
//Abre la ayuda contextual, en la posición del cursor.
var p:TPoint;
begin
  //calcula posición donde aparecerá el menú de completado
  p := Point(ed.CaretXPix,ed.CaretYPix + ed.LineHeight);
  p.X:=Max(0,Min(p.X, ed.ClientWidth - MenuComplet.Width));
  p := ed.ClientToScreen(p);
  //Abre menú contextual, llamando primero a OnExecute(). Solo se mostrará si tiene elementos.
  MenuComplet.Execute('<KeyUp>', p.x, p.y);   //pasa una clave cualquiera para identificación posterior
End;
procedure TSynFacilComplet.CloseCompletionWindow;
//Cierra la ventana del menú contextual
begin
  MenuComplet.Deactivate;
end;
constructor TSynFacilComplet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  curEnv   := TFaCursorEnviron.Create(self);
  OpenPatterns := TFaOpenEvents.Create(True);
  CompletLists := TFaCompletionLists.Create(true);
  CaseSensComp := false;  //por defecto
  CompletionOn := true;  //activo por defecto
  SelectOnEnter := true;
  vKey := 0;     //limpia
  vShift := [];  //limpia
  utKey := '';   //limpia
end;
destructor TSynFacilComplet.Destroy;
begin
  if MenuComplet<>nil then MenuComplet.Destroy;  //por si no lo liberaron
  CompletLists.Destroy;
  OpenPatterns.Destroy;
  curEnv.Destroy;
  inherited Destroy;
end;

end.


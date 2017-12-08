param ( [string]$AssemblyName = "System.Management.Automation", [string]$ExclusionFile = "Exclusions.json" )
$assembly = [appdomain]::CurrentDomain.GetAssemblies() | ?{$_.Location -match $AssemblyName}

function Get-Exclusions
{
    param ( $exclusionFile )
    $script:ExcludedItems = get-content $exclusionFile | ConvertFrom-Json
}

function Fix-Name ( $name ) 
{
    $cSharpKeywords = "abstract","as","base","bool","break","byte","case","catch","char","checked","class","const",
        "continue","decimal","default","delegate","do","double","else","enum","event","explicit","extern","false",
        "finally","fixed","float","for","foreach","goto","if","implicit","in","int","interface","internal","is",
        "lock","long","namespace","new","null","object","operator","out","override","params","private","protected",
        "public","readonly","ref","return","sbyte","sealed","short","sizeof","stackalloc","static","string","struct",
        "switch","this","throw","true","try","typeof","uint","ulong","unchecked","unsafe","ushort","using","virtual",
        "void","volatile","while"
    if ( $cSharpKeywords -contains $name ) { return "@${name}" } else { return "${name}" }
}


function Exclude-Member ( $name ) {
    #$script:namespace
    #$script:CurrentClass
    foreach($member in $ExcludedItems.classmember) {
        if ( $name -eq $member.property -and $script:namespace -eq $member.namespace -and $script:CurrentClass -eq $member.class )
        {
            return $true
        }
    }
    return $false
}

function Exclude-Class ( $name ) {
    foreach ($class in $ExcludedItems.class) {
        if ( $name -eq $class.class -and $script:namespace -eq $class.namespace ) { return $true }
    }
    return $false
}

function Get-tType ( $tType )
{
    $p = @()
    if ( $tType.IsGenericType ) {
        $pp = $tType.FullName
        if ( ! $pp ) { $pp = $tType.Namespace + "." + $tType.Name }
        $pp = Get-TypeNickname ( $pp -replace "``.*" )
        $gp = @()
        $argsAndParms = @(); $argsAndParms += $tType.GenericTypeArguments; $argsAndParms += $tType.GenericTypeParameters
        foreach( $pt in $argsAndParms ) { # $tType.GenericTypeArguments) {
            if ( $pt.IsGenericType )
            {
                $gp += Get-tType $pt
            }
            else {
                $aa = $pt.FullName
                if ( ! $aa ) { $aa = $pt.Name }
                $gp += Get-TypeNickname $aa
            }
        }
        $ss = $gp -join ", "
        if ( $ss -eq "" ) { wait-debugger }
        $p += "{0}<{1}>" -f $pp, $ss
    }
    else {
        $p += Get-TypeNickname $tType.FullName
    }
    $p -join ", "
}


function GetTypeName ( $type )
{
    if ( $type.IsGenericTypeDefinition -or $type.IsGenericType) {
        $names = $type.GenericTypeParameters.Name
        $tname = Get-TypeNickname $type.fullname
        if ( ! $tname ) { $tname = Get-TypeNickname $type.name }
        if ( ! $names ) { 
            $names = $type.GenericTypeArguments 
        }
        $tname = Get-TypeNickname $tname
        "{0}<{1}>" -f ($tname -replace "``.*"),($names -join ",")
    }
    else {
        $type.name
    }
}

function Get-TypeNickname ( [string]$typename )
{
    $TypeTranslation = @{
        "Object"          = "object"
        "System.Object"   = "object"
        "Object[]"        = "object[]"
        "System.Object[]" = "object[]"
       
        "Boolean"         = "bool"
        "System.Boolean"  = "bool"

        "String[]"        = "string[]"
        "System.String[]" = "string[]"
        "String"          = "string"
        "System.String"   = "string"

        "Int32"           = "int"
        "System.Int32"    = "int"
        "UInt32"          = "uint"
        "System.UInt32"   = "uint"

        "Void"            = "void"
        "System.Void"     = "void"

        "System.Char"     = "char"
        "Char"            = "char"

        "System.Char[]"   = "char[]"
        "Char[]"          = "char[]"


    }

    $typename = $typename -replace "\+","."
    $typename = $typename -replace "``.*"
    $v = $TypeTranslation["$typename"]
    if ( $v ) { return $v } else { return $typename }
}

function IsStaticClass ( $Type )
{
    if ( $Type.IsAbstract -and $Type.IsSealed ) { "static" }
}

function IsSealedClass ( $Type ) {
    if ( $Type.IsEnum ) { return }
    if ( $Type.IsSealed -and ! $Type.IsAbstract ) { "sealed" }
}

function IsAbstract ( $Type ) {
    if ( $type.IsAbstract -and ! $Type.IsSealed ) { "abstract" }
}

function GetTypeType ( $type )
{
    if ( $type.IsInterface ) { return "interface" }
    if ( $type.IsClass ) { return "class" }
    if ( $type.IsEnum -and $type.IsValueType ) { return "enum" }
    if ( $type.IsValueType -and ! $type.IsEnum ) { return "struct" }
    Write-Warning ($type.Name + " is unknown")
    return "unknown"
}

function EmitEnum ( $t )
{
    $names = [enum]::GetNames($t) | sort-object
    $names | %{
        "    $_ = {0}," -f ($t::"$_").value__
    }
}

function EmitConstants ( $t )
{
    $attrs = [reflection.fieldattributes]"Literal,HasDefault"
    $constants = $t.GetFields("Static,Instance,Public,DeclaredOnly")|
        where-object {$_.Attributes -band $attrs}|
        where-object {$_.FieldType.FullName -eq "system.string"}|
        sort-object Name
    $constantCount = $constants.Count
    foreach ( $constant in $constants )
    {
        if ( $t.IsAbstract -and ! $t.IsSealed ) { $visibility = "protected" } else { $visibility = "public" }
        $fieldType = Get-TypeNickname $constant.FieldType
        $fieldName = $constant.Name
        $fieldValue= $constant.GetValue($null)
        $multiline = ""
        if ( $fieldValue -match "`n" ) { $multiline = "@" }
        $fmt = '    {0} const {1} {2} = {3}"{4}";' 
        $fmt -f $visibility,$fieldType,$fieldName,$multiline,$fieldValue
        #$fmt -f $visibility,(Get-TypeNickname $constant.FieldType),$constant.Name,$constant.GetValue($null)
        #$const += "const "
        #$const += Get-TypeNickname $constant.FieldType
        #$const += " "
        #$const += $constant.Name
        #$const += " = "
        #$const += '"{0}";' -f $constant.GetValue($null)
        #$const
    }
}

function EmitAttribute ( $t )
{
    if ( ! $t.CustomAttributes ) { return }
    foreach ( $attribute in $t.CustomAttributes )
    {
        $at = Get-tType $attribute.AttributeType
        $s = "    [" + (get-TypeNickname $at)
        if ( $attribute.ConstructorArguments -or $attribute.NamedArguments ) { $s += "(" }
        $aArgs = @()
        $aArgs += $attribute.ConstructorArguments
        $aArgs += $attribute.NamedArguments
        $s += $aArgs -join ", "
        if ( $attribute.ConstructorArguments -or $attribute.NamedArguments ) { $s += ")" }
        $s += "]"
        $s
    }
}

function EmitProperties ( $t )
{
    $properties = $t.GetProperties("Static,Instance,Public,DeclaredOnly")| sort-object Name
    $propertyCount = $properties.Count
    foreach ( $Property in $properties)
    {
        # emit the member only if not excluded
        if ( Exclude-Member $property.name ) { $propertyCount--; continue }
        # check for generic
        $propertyString = Get-tType $property.propertytype
        #if ( $Property.PropertyType.IsGenericType ) {
        #    #wait-debugger
        #    $propertyArgs = $property.propertytype.GenericTypeArguments | %{ $a = @()}{$a += Get-TypeNickName $_.fullname}{$a -join ","}
        #    $propertyType = $property.propertytype.fullname -replace "``.*"
        #    $propertyString = "{0}<{1}>" -f $propertyType,$propertyArgs
        #}
        #else {
        #    $propertyString = Get-TypeNickName $property.propertytype.fullname
        #}
        [string]$dec = ""
        # Attributes
        if ( $property.CustomAttributes ) {
            $attributes = $property.CustomAttributes | Sort-Object AttributeType
            foreach($attribute in $attributes) {
                if ( ! $attribute.ConstructorArguments ) {
                    $dec += "    [" + (Get-TypeNickname $attribute.AttributeType.FullName) + "]"
                    # if ( $attribute.AttributeType.Fullname -match "\+" ) { wait-debugger }
                }
                else {
                    $dec += "    ${attribute}`n" # -replace "\(\)","" -creplace " String"," string" -creplace " True","true" -creplace " False","false"
                }
                # if ( "$attribute" -match "\+" ) { wait-debugger }
            }
        }
        if ( $t.IsInterface ) {
            "    {0} {1} {{ get; }}" -f $propertyString,$property.name
        }
        else {
            $dec += "    public {0} {1} {{" -f $propertyString,$property.name
            if ( $property.GetMethod ) { $dec += " get { return default($propertyString); }" }
            if ( $property.SetMethod ) { $dec += " set { }" }
            $dec += " }" 
        }
        $dec
    }
}

function EmitConstructors ( $t )
{
    $constructors = $t.GetConstructors("Public,NonPublic,Instance")
    $constructorCount = $constructors.Count
    foreach ($constructor in $constructors) {
        $dec = ""
        if ( $constructor.IsPublic ) { $dec += "    public " }
        elseif ( $constructor.IsFamily ) { $dec += "    protected " }
        elseif ( ! $constructor.IsFamily -and ! $constructor.IsPublic ) { $constructorCount--; continue } # don't emit

        $name = $t.Name -replace "``.*"
        $params = GetParams $constructor
        $dec += $name 
        $dec += "("
        $dec += $params
        $dec += ") { }"
        $dec

        <#
        $params = $constructor.GetParameters()
        if ( $params.Count -eq 0 ) {
            $dec += $Name + "()"
        }
        else {
            $dec +=  $Name + "("
            $par = @()
            foreach( $param in $params ) {
                $par += "{0} {1}" -f (Get-TypeNickname $param.parametertype.FullName), $param.name
            }
            $dec += $par -join ", "
            $dec += ")"
        }
        $dec += "{ }"
        $dec -join " "
        #>
    }
    if ( $constructorCount -gt 0 ) { "" }
}

function GetParams ( $method )
{
    $parm = @()
    foreach($p in $method.GetParameters()) {
        $pType = Get-tType $p.parametertype
        if ( $pType -match "&$" ) { $pType = $pType.TrimEnd("&") ; $isOut = "out " } else { $isOut = "" }
        $parm += "${isout}{0} {1}" -f $pType,(Fix-Name $p.Name)

    # JWT
        <#
        $paramType = $p.parametertype.FullName
        if ( ! $paramType ) { $paramType = $p.parametertype.Name }
        $pTypeName = Get-TypeNickname $paramType
        if ( $pTypeName -match "&$" ) { $pTypeName = $pTypeName.TrimEnd("&"); $isOut = "out " } else { $isOut = "" }
        if ( $p.ParameterType.IsGenericType )
        {
            $pTypeName += "<" + ($p.ParameterType.GenericTypeArguments -join ",") + ">"
        }
        $parm += "${isout}{0} {1}" -f $pTypeName,$p.name
        #>
    }
    return ($parm -join ", ")
}

function GetDefaultReturn ( $method, $rt ) {
    if ( $method.ReturnType.Name -ne "void" ) {
        "return default($rt);"
        #if ( $method.ReturnType.IsGenericType ) {
        #    "return default(" + ($method.ReturnType.ToString() -replace "``.*") + ");" 
        #}
        #else {
        #    "return default(" + ( Get-TypeNickname $method.ReturnType.FullName ) + ");"
        #}
    }
}

function Get-NestedTypes ( $t ) {
    $t.GetNestedTypes("Public,Instance,Static")
}

function Get-MethodNameAndReturnType ( $method, [ref] $returnT )
{
    $name = $method.name
    #$returnType = Get-TypeNickname (GetTypeName $method.ReturnType)
    $returnType = Get-TypeNickname (Get-tType $method.ReturnType)
    $returnT.Value = $returnType
    switch ( $name ) {
        "op_Equality"           { "${returnType} operator =="; break }
        "op_GreaterThan"        { "${returnType} operator >"; break }
        "op_GreaterThanOrEqual" { "${returnType} operator >="; break }
        "op_Inequality"         { "${returnType} operator !="; break }
        "op_LessThan"           { "${returnType} operator <"; break }
        "op_LessThanOrEqual"    { "${returnType} operator <="; break }

        "op_Explicit"           { "explicit operator ${returnType}"; break }
        "op_Implicit"           { "implicit operator ${returnType}"; break }
        default { 
            "${returnType} ${name}" 
            }
    }
}

function EmitMethods ( $t )
{
    $methods = $t.GetMethods("Instance,Static,NonPublic,Public,DeclaredOnly") | sort-object name
    $methodCount = $methods.Count
    $IsInterface = $t.IsInterface
    foreach ( $method in $methods ) {
        if ( $method.name -cmatch "^[gs]et_|^add_|^remove_" ) { $methodCount--; continue }
        $sig = @()
        if ( $IsInterface ) {
            $sig += "    "
        }
        elseif ( $method.IsFamilyOrAssembly ) {
            $sig += "    protected internal"
        }
        elseif ( $method.IsPublic ) {
            $sig += "    public"
        }
        elseif ( $method.IsVirtual -and $method.IsFamily ) {
            $sig += "    protected"
        }
        else {
            $methodCount--
            continue; # don't emit
        }
        if ( $method.IsVirtual -and ! $t.IsInterface ) { 
            if ( $t.IsAbstract ) {
                $sig += "virtual" 
            }
            else {
                $sig += "override" 
            }
        }
        if ( $method.IsStatic ) { $sig += "static" }
        $rt = $null
        $mrt = Get-MethodNameAndReturnType $method ([ref]$rt)
        #if ( $mrt -match "IEnum.*Invoke") { wait-debugger }
        #if ( $mrt.length -eq 0 ) { wait-debugger }
        $sig += $mrt
        #if ( $method.name -match "^op_" ) {
        #    $sig += (Get-MethodName $method.name)
        #    $sig += Get-TypeNickname (GetTypeName $method.ReturnType) # .FullName
        #}
        #else {
        #    $sig += Get-TypeNickname (GetTypeName $method.ReturnType) # .FullName
        #    $sig += $method.name # (Get-MethodName $method.name)
        #}
        $sig += "("
        #$sig += $method.Name + "("
        $sig += GetParams $method
        if ( $IsInterface ) {
            $sig += ");"
        }
        else {
            $sig += ") {"
            $sig += GetDefaultReturn $method $rt
            $sig += "}"
        }
        $sig -join " "
    }
    if ( $methodCount -gt 0 ) { "" }


}

function EmitEvents ( $t )
{
    $events = $t.GetEvents("Instance,Static,NonPublic,Public,DeclaredOnly") | sort-object name
    $isAbstract = $t.IsAbstract
    foreach ( $event in $events ) {
        $eventString = ""
        $eventString = "    public"
        if ( $t.IsAbstract ) { $eventString += " abstract" }
        elseif ( $t.IsStatic ) { $eventString += " static" }
        $eventString += " event"
        $eventString += " " + $event.EventHandlerType.ToString() -replace "``.\[","<" -replace "\]",">"
        $eventString += " " + $event.Name
        $eventString += " { add { } remove { } }"
        $eventString
    }
    if ( $events.Count -gt 0 ) { "" }
}

if ( $assembly.GetType().FullName -ne "System.Reflection.RuntimeAssembly" )
{
    throw "'$AssemblyName' is not a runtime assembly"
}

function GetBaseType ( $type )
{
    $BaseType = $type.BaseType.FullName
    if ( $type.isClass -and $type.isgenerictypedefinition ) { 
        $s = ""
        if ( $type.ImplementedInterfaces ) {
            $iface = $type.ImplementedInterfaces | %{ Get-TypeNickName $_ }
            $s += ": " + ($iface -join ", ")
        }
        $ga = $type.GetGenericArguments()
        if ( $ga ) {
            $s += "where {0} : {1}" -f ($ga.Name -join ", "),(($ga.BaseType|%{"$_" -replace "System.ValueType","struct, System.IConvertible"}) -join ", ")
        }
        return $s
        #$ttype = $type.GetGenericArguments().Name
        #$constraints = @()
        #if ( $type.StructLayoutAttribute ) { $constraints += "struct" }
        #$contraints += $type.ImplementedInterfaces | %{ Get-TypeNickname $_ }
        #$constraints += $type.GenericTypeParameters.ImplementedInterfaces | %{ Get-TypeNickname $_ }
        # return ("where ${ttype} : {0}" -f ($constraints -join ", "))
    }
    switch ( $BaseType ) {
        "System.Object" { return }
        "System.Enum" { return }
        default { return ": $BaseType" }
    }
}

function Get-TypeAttribute
{
    param ( [Type]$t )
    #[string[]]$t.CustomAttributes | %{ "   $_" }
    #$attrs = $t.GetCustomAttributes($false)
    $attrs = $t.CustomAttributes
    foreach ( $attr in $attrs )
    {
        if ( @($attr.ConstructorArguments).Length -eq 0 -and @($attr.NamedArguments).Length -eq 0 ) {
            "[{0}]`n" -f (Get-TypeNickname ($attr.AttributeType))
            continue
        }
        #switch ( $attr.TypeId )
        switch ( $attr.AttributeType.FullName )
        {
            "System.Management.Automation.ParameterAttribute" {
            }
            "System.Management.Automation.CmdletAttribute" {
                "   {0}`n" -f [string]$attr
                #"   [{0}(""{1}"",""{2}"")]`n" -f $_,$attr.VerbName,$attr.NounName
            }
            "System.AttributeUsageAttribute" {
                "   ${attr}`n"
            }
            "System.CodeDom.Compiler.GeneratedCodeAttribute" {
                "   ${attr}`n"
            }
            "System.ComponentModel.TypeConverterAttribute" {
                "   ${attr}`n"
            }
            "System.ComponentModel.TypeDescriptionProviderAttribute" {
                "   ${attr}`n"
            }
            "System.Diagnostics.DebuggerDisplayAttribute" {
                "   ${attr}`n"
            }
            "System.FlagsAttribute" {
                "   ${attr}`n"
            }
            "System.Management.Automation.OutputTypeAttribute" {
                #"   [$_(new {0}{{{1}}},{2})]`n" -f $attr.ConstructorArguments.ArgumentType,($attr.ConstructorArguments.Value -join ", "), ($attr.NamedArguments -join ", ")
                "  ${attr}`n"
            }
            "System.Management.Automation.Provider.CmdletProviderAttribute" {
                "   ${attr}`n"
            }
            "System.Reflection.DefaultMemberAttribute" {
                "   ${attr}`n"
            }
            "System.Runtime.CompilerServices.ExtensionAttribute" {
                "   ${attr}`n"
            }
            "System.Runtime.Serialization.DataContractAttribute" {
                "   {0}`n" -f (${attr} -replace "\(\)")
            }
            "System.SerializableAttribute" {
                "   ${attr}`n"
            }
            "System.Xml.Serialization.XmlTypeAttribute" {
                "   ${attr}`n"
            }
            default {
                "DEFAULT ${attr}`n"
            }
        }
    }
}




function EmitInterface ( $t )
{
    "// INTERFACE: $t"
    "  public partial interface " + $t.Name + " {"
    EmitProperties $t
    EmitMethods $t
    "  }"
}

function EmitStruct ( $t )
{
    # constructor
    # properties
    # methods
    "// STRUCT"
    "  public partial struct " + $t.Name + " {"
    EmitConstructors $t
    EmitProperties $t
    EmitMethods $t
    "  }"
}

Get-Exclusions $ExclusionFile

$Types = $assembly.GetTypes() |?{$_.IsPublic}
$NamespaceTypes = $Types | Group-Object Namespace 
foreach ( $g in $NamespaceTypes ) {
    if ( $ExcludedItems.namespace -contains $g.Name ) { Write-Warning ("Skipping "+ $g.Name); continue }
    # if ( $g.Name -ne "Microsoft.PowerShell.Cmdletization" ) { continue }
    Write-Progress -Id 0 $g.Name
    $script:namespace = $g.Name
    "namespace {0} {{" -f $g.Name
    foreach ( $t in $g.Group | sort-object Name) {
        Write-Progress -Parent 0 -Id 1 $t
        $typeName = (GetTypeName $t) -replace "^.*\." # which includes generics
        $dec = @()
        $dec += Get-TypeAttribute $t
        $dec += "  public"
        $dec += IsAbstract $t
        $dec += IsStaticClass $t
        $dec += IsSealedClass $t
        $dec += GetTypeType $t
        $dec += $typeName
        $dec += GetBaseType $t
        $dec += "{"
        $typetype = GetTypeType $t
        # "  public {0} {1} {2} {{" -f (IsStaticClass $t), (GetTypeType $t), $t.Name
        switch ( $typetype ) {
            "enum" {
                $dec -join " "
                EmitEnum $t
                "  }"
                break
            }
            # handle interface!!!!
            "interface" {
                EmitInterface $t
            }
            "struct" {
                EmitStruct $t
            }
            "class" {
                $script:CurrentClass = $typeName
                if ( Exclude-Class $typeName ) { continue }
                #if ( $typeName -eq "VerbsOther" ) { wait-debugger }
                $dec -join " "
                EmitConstructors $t
                EmitConstants $t
                EmitEvents $t
                EmitProperties $t
                EmitMethods $t
                "  }"
                break
            }
            default {
                Write-Error "Unknown $t"
                break
            }
        }
        ""
    }
    "}"
    # ONLY DO ONE FOR TESTING
}

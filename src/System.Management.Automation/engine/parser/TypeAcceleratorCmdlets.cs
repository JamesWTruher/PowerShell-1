// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Management.Automation;
using System.Text;

namespace System.Management.Automation.Language
{
	/// <summary>
	/// The object we will return if found.
	/// </summary>
	public class TypeAcceleratorInfo
	{
		/// <summary>
		/// The accelerator string.
		/// </summary>
		public string Name;
		/// <summary>
		/// The accelerator type.
		/// </summary>
		public Type Type;

		/// <summary>
		/// constructor.
		/// </summary>
		public TypeAcceleratorInfo(string name, Type type)
		{
			Name = name;
			Type = type;
		}

        /// <summary>
        /// ToString override.
        /// </summary>
        public override string ToString()
        {
            return string.Format(CultureInfo.InvariantCulture, "{0} => {1}", Name, Type);
        }
	}

	/// <summary>
	/// The Get-TypeAccelerator cmdlet.
	/// </summary>
	[Cmdlet(VerbsCommon.Get, "TypeAccelerator", DefaultParameterSetName = "name")]
    public class GetTypeAcceleratorCommand : PSCmdlet
    {
        /// <summary>
        /// the name of the accelerator.
        /// </summary>
		[Parameter(ParameterSetName="name", Position = 0)]
        [Alias("Name")]
        [SupportsWildcards]
        public string[] AcceleratorName { get; set; }

        /// </summary>
        /// the type of the accelerator.
        /// </summary>
		[Parameter(ParameterSetName="type", Position = 0)]
        [Alias("Type")]
        public Type[] AcceleratorType { get; set; }

        internal HashSet<string> _names = new HashSet<string>();

        /// <summary>
        /// Start by collecting the type accelerator names.
        /// </summary>
        protected override void BeginProcessing()
        {
            foreach (var k in TypeAccelerators.Get.Keys)
            {
                _names.Add(k.ToString());
            }
        }

		/// <summary>
		/// Get the type accelerator.
		/// </summary>
        protected override void ProcessRecord()
        {
			Type result;
			if (AcceleratorName is null && AcceleratorType is null)
			{
				foreach (var name in _names)
				{
					WriteObject(new TypeAcceleratorInfo(name, TypeAccelerators.Get[name]));
				}
				return;
			}

			if (ParameterSetName.CompareTo("name") == 0)
			{
				foreach (var name in AcceleratorName) {
                    if (WildcardPattern.ContainsWildcardCharacters(name))
                    {
                        var pattern = WildcardPattern.Get(name, WildcardOptions.IgnoreCase);
                        foreach (var k in _names)
                        {
                            if (pattern.IsMatch(k))
                            {
                                WriteObject(new TypeAcceleratorInfo(k, TypeAccelerators.Get[k]));
                            }
                        }
                    }
                    else if (TypeAccelerators.Get.TryGetValue(name, out result))
                    {
                        WriteObject(new TypeAcceleratorInfo(name, result));
                    }
				}
			}
			else
			{
				foreach (var type in AcceleratorType) {
					foreach (var k in TypeAccelerators.Get.Keys) {
						if (TypeAccelerators.Get[k] == type) {
							WriteObject(new TypeAcceleratorInfo(k.ToString(), TypeAccelerators.Get[k]));
						}
					}
				}
			}
        }
    }

    /// <summary>
    /// The Add-TypeAccelerator cmdlet.
    /// </summary>
    [Cmdlet(VerbsCommon.Add, "TypeAccelerator")]
    public class AddTypeAcceleratorCommand : PSCmdlet
    {
        /// <summary>
        /// the name of the accelerator.
        /// </summary>
        [Parameter(Mandatory=true, ValueFromPipelineByPropertyName=true, Position = 0)]
        public string Name { get; set; }

        /// <summary>
        /// Pass the accelerator back.
        /// </summary>
        [Parameter()]
        public SwitchParameter PassThru { get; set; }

        /// <summary>
        /// the type of the accelerator.
        /// </summary>
        [Parameter(Mandatory=true, ValueFromPipelineByPropertyName=true, Position = 1)]
        public Type Type { get; set; }

        /// <summary>
        /// Add the type accelerator.
        /// </summary>
        protected override void ProcessRecord()
        {
            if (!TypeAccelerators.Get.TryGetValue(Name, out Type _))
            {
                TypeAccelerators.Add(Name, Type);
                if (PassThru)
                {
                    WriteObject(new TypeAcceleratorInfo(Name, Type));
                }
            }
        }
    }

    /// <summary>
    /// The Remove-TypeAccelerator cmdlet.
    /// </summary>
    [Cmdlet(VerbsCommon.Remove, "TypeAccelerator", ConfirmImpact = ConfirmImpact.High, SupportsShouldProcess = true)]
    public class RemoveTypeAcceleratorCommand : PSCmdlet
    {
        /// <summary>
        /// the name of the accelerator.
        /// </summary>
        [Parameter(Mandatory=true, Position = 0)]
        public TypeAcceleratorInfo[] Accelerator { get; set; }

        /// <summary>
        /// Remove the type accelerator.
        /// </summary>
        protected override void ProcessRecord()
        {
            foreach (var acceleratorInfo in Accelerator)
            {
                if (ShouldProcess(acceleratorInfo.ToString()))
                {
                    TypeAccelerators.Remove(acceleratorInfo.Name);
                }
            }
        }
    }
}

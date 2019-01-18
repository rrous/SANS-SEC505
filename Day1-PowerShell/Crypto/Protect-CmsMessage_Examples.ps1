﻿<# 
This script provides examples of the following cmdlets:

    Protect-CmsMessage
    Unprotect-CmsMessage
    Get-CmsMessage

Cryptographic Message Syntax (CMS) is defined by RFC5652
(http://tools.ietf.org/html/rfc5652) and provides for the
encryption and/or signing of data using a public key.


***OS and PowerShell Requirements***
The above CMS cmdlets require Windows 10, Server 2016, 
PowerShell 5.0, or later.

The data to be encrypted must be smaller than 2GB.


Errors:
Trying to encrypt a file larger than 2GB:
    Protect-CmsMessage : The file is too long. This operation is currently limited to supporting files less than 2 gigabytes in size.

When trying to encrypt a 1GB file (with 32GB of RAM and a fresh relaunch of PowerShell_ISE.exe):
    Protect-CmsMessage : Exception of type 'System.OutOfMemoryException' was thrown.

With a 300MB CMS file:
    Unprotect-CmsMessage : ASN1 value too large.
    Get-CmsMessage : ASN1 value too large.




***Public Key Certificate Requirements***

Encryption certificates must contain the "Data Encipherment" or 
"Key Encipherment" key usage, and include the "Document Encryption"
enhanced key usage (EKU = 1.3.6.1.4.1.311.80.1).

This means that, in the certificate template, on the Request Handling
tab, "Encryption" or "Signature and Encryption" must be selected, and,
on the Extensions tab, select Application Policies, then add "Document
Encryption" to the list of Application Policies.

To confirm that the intended certificate meets the requirements, 
open the certificate, Details tab, confirm that the "Enhanced Key
Usage" property at least includes:

    Document Encryption (1.3.6.1.4.1.311.80.1)

And that the "Key Usage" property at least includes:

    Key Encipherment (20)



***The -To Parameter***

The certificate can be given to the cmdlet in various ways:

    * Path to an exported certificate file (.cer)
    * Path to a directory containing one exported certificate file (.cer) --Jason, one or many?
    * Thumbprint hash value of the certificate in the user's cert:\ drive
    * The certificate's subject name, to be found in the user's cert:\ drive
    * A certificate object stored in a variable

If the folder path given has multiple certificates, the first one returned will
be used.  If that certificate is not acceptable for any reason, the cmdlet
returns a terminating error and does not attempt to use any other certs in the
folder.  

The output of Protect-CmsMessage will be Base64 ciphertext.

See the following for interoperability with OpenSSL:
http://blogs.msdn.com/b/powershell/archive/2015/06/09/powershell-the-blue-team.aspx

#>


# To encrypt the contents of a variable using an exported certificate:
$x = get-process #Some object data to protect
Protect-CmsMessage -To .\ExportedCert.cer -Content $x -OutFile EncryptedVar.cms


# To encrypt a TEXT file using an exported certificate, saving the output to a new file:
Protect-CmsMessage -To .\ExportedCert.cer -Path .\SecretDocument.txt -OutFile EncryptedDoc.cms


# To encrypt a variable or TEXT file using an exported certificate, capturing the output to a new variable:
$CipherText1 = Protect-CmsMessage -To .\ExportedCert.cer -Content $x 
$ciphertext2 = Protect-CmsMessage -To .\ExportedCert.cer -Path .\SecretDocument.txt


# To obtain metadata from some CMS ciphertext, but not decrypt it:
Get-CmsMessage -Content $CipherText1
Get-CmsMessage -Path .\EncryptedDoc.cms


# To decrypt CMS ciphertext, assuming you have the private key:
$plaintext = Unprotect-CmsMessage -Path .\EncryptedVar.cms
$plaintext = Unprotect-CmsMessage -Content $CipherText1
$plaintext = Unprotect-CmsMessage -Path .\EncryptedFile.cms


# ***Objects and (No) Property Bags***
#
# But when an object is encrypted, it is only the string representation of that 
# object which gets encrypted, not the whole "property bag" of the object; hence,
# it is not (usually) possible to recreate the original object in memory again
# like with Import-Csv or Import-CliXml.  If you want to reflate an array of
# objects in memory after decryption with Unprotect-CmsMessage, first convert
# the array to CSV or XML string data, encrypt with Protect-CmsMessage, decrypt
# with Unprotect-CmsMessage, then reflate the objects from the plaintext CSV or
# XML data.



# *** Using Get-CmsMesssage ***

# Display metadata about a CMS message, but not decrypt it:
Get-CmsMessage -Path .\little.cms
"test data" | Protect-CmsMessage -To .\ExportedCert.cer | Get-CmsMessage

# The output may scroll by for several pages, so this will display just
# some of the metadata, and in a hopefully more-useful form:

Get-CmsMessage -Path .\little.cms | Select -ExpandProperty Recipients 
(Get-CmsMessage -Path .\little.cms).Recipients

Get-CmsMessage -Path .\little.cms | Select -ExpandProperty ContentInfo | Select -ExpandProperty ContentType
(Get-CmsMessage -Path .\little.cms).ContentInfo.ContentType.FriendlyName

Get-CmsMessage -Path .\little.cms | Select -ExpandProperty ContentEncryptionAlgorithm | Select -ExpandProperty Oid
(Get-CmsMessage -Path .\little.cms).ContentEncryptionAlgorithm.Oid.FriendlyName




# ***Binary Files***
#
# What about encrypting and decrypting binary files?
# This pair of commands DOES NOT WORK, they fail to restore the original file!
# Nor can you specify -Encoding Byte for Set-Content: this raises an error
# because the output of Unprotect-CmsMessage is a string, not a byte[] array.

Protect-CmsMessage -To .\ExportedCert.cer -Path .\InputFile.exe -OutFile OutputFile.cms
Unprotect-CmsMessage -Path .\OutputFile.cms | Set-Content -Path RestoredFile.exe

# When the original file and the restored files are hashed, the hashes will NOT match:
Get-FileHash -Path .\InputFile.exe,.\RestoredFile.exe 



# But if a file is converted to Base64 first, the Base64 text can be encrypted safely:

function Convert-FromBinaryFileToBase64 
{ 
    [CmdletBinding()] 
    Param
    ( 
      [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)] $Path,
      [Switch] $InsertLineBreaks
    )

    if ($InsertLineBreaks){ $option = [System.Base64FormattingOptions]::InsertLineBreaks }
    else { $option = [System.Base64FormattingOptions]::None }

    [System.Convert]::ToBase64String( $(Get-Content -ReadCount 0 -Encoding Byte -Path $Path) , $option )
} 



function Convert-FromBase64ToBinaryFile 
{ 
    [CmdletBinding()] 
    Param( [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]  $String , 
           [Parameter(Mandatory = $True, Position = 1, ValueFromPipeline = $False)] $OutputFilePath )

    [System.Convert]::FromBase64String( $String ) | Set-Content -OutputFilePath $Path -Encoding Byte 

} 


# Convert the binary file to Base64 strings, then encrypt:
dir .\InputFile.exe | Convert-FromBinaryFileToBase64 | Protect-CmsMessage -To .\ExportedCert.cer -OutFile OutputFile.cms


# Then the file can be decrypted and the Base64 converted back into a binary file again;
# however, the performance of these operations is terrible!  A 20MB binary file will 
# require 10 minutes or more to decrypt on a typical desktop computer.  Zip-compress the
# binary file first before Base64 encoding and CMS encryption.
Unprotect-CmsMessage -Path .\OutputFile.cms | Convert-FromBase64ToBinaryFile -OutputFilePath .\RestoredFile.exe 


# But at least when the original and restored files are hashed, the hashes will indeed match:
Get-FileHash -Path .\InputFile.exe,.\RestoredFile.exe 


# Because of the performance issues, if you must encrypt more than a few megabytes of data,
# use a tool like 7-Zip to compress and encrypt the data quickly using a 200+ character
# random passphrase, then encrypt the passphrase with Protect-CmsMessage.  See the script
# named New-7zipArchive.ps1 in the SEC505 collection of scripts for an example that 
# could be modified for this purpose.  The Compress-Archive cmdlet does not currently 
# support a passphrase parameter to encrypt the zip output file.



# ***Embedded Certificate in Script***
#
# The certificate used by Protect-CmsMessage can be embeeded in the script itself.



# First, get the public key certificate into a byte array from a file.
[Byte[]] $CertBytes = Get-Content -Encoding Byte -Path ".\ExportedCert.cer"


# Next, convert the cert byte[] array to hex:


function Convert-ByteArrayToHexString 
{
################################################################
#.Synopsis
#   Returns a hex representation of a System.Byte[] array as
#   one or more strings. Hex format can be changed.
#.Parameter ByteArray
#   System.Byte[] array of bytes to put into the file. If you
#   pipe this array in, you must pipe the [Ref] to the array.
#   Also accepts a single Byte object instead of Byte[].
#.Parameter Width
#   Number of hex characters per line of output.
#.Parameter Delimiter
#   How each pair of hex characters (each byte of input) will be
#   delimited from the next pair in the output. The default
#   looks like "0x41,0xFF,0xB9" but you could specify "\x" if
#   you want the output like "\x41\xFF\xB9" instead. You do
#   not have to worry about an extra comma, semicolon, colon
#   or tab appearing before each line of output. The default
#   value is ",0x".
#.Parameter Prepend
#   An optional string you can prepend to each line of hex
#   output, perhaps like '$x += ' to paste into another
#   script, hence the single quotes.
#.Parameter AppendComma
#   Appends a comma to each line of output, except the last.
#.Parameter AddQuotes
#   A switch which will enclose each line in double-quotes.
#.Example
#   [Byte[]] $x = 0x41,0x42,0x43,0x44
#   Convert-ByteArrayToHexString $x
#
#   0x41,0x42,0x43,0x44
#.Example
#   [Byte[]] $x = 0x41,0x42,0x43,0x44
#   Convert-ByteArrayToHexString $x -width 2 -delimiter "\x" -addquotes
#
#   "\x41\x42"
#   "\x43\x44"
################################################################
    [CmdletBinding()] 
    Param 
    (
     [Parameter(Mandatory = $True, ValueFromPipeline = $True)] [System.Byte[]] $ByteArray,
     [Parameter()] [Int] $Width = 10,
     [Parameter()] [String] $Delimiter = ",0x",
     [Parameter()] [String] $Prepend = "",
     [Parameter()] [Switch] $AddQuotes,
     [Parameter()] [Switch] $AppendComma 
    )

    if ($Width -lt 1) { $Width = 1 }
    if ($ByteArray.Length -eq 0) { Return }
    $FirstDelimiter = $Delimiter -Replace "^[\,\\:\t]",""
    $From = 0
    $To = $Width - 1
    Do
    {
    $String = [System.BitConverter]::ToString($ByteArray[$From..$To])
    $String = $FirstDelimiter + ($String -replace "\-",$Delimiter)
    $From += $Width
    $To += $Width
    if ($AppendComma -and $From -lt $ByteArray.Length) { $String = $String + ',' } 
    if ($AddQuotes) { $String = '"' + $String + '"' }
    if ($Prepend -ne "") { $String = $Prepend + $String }
    $String
    } While ($From -lt $ByteArray.Length)
} 
 

# Copy the hex strings to the clipboard:
Convert-ByteArrayToHexString -ByteArray $CertBytes -AppendComma | Set-Clipboard


# Paste the hex strings into your script to make a Byte[] array.
# Notice how each line ends with a comma indicating line continuation:

[Byte[]] $CertBytes =
0x30,0x82,0x06,0xB4,0x30,0x82,0x04,0x9C,0xA0,0x03,
0x02,0x01,0x02,0x02,0x13,0x5B,0x00,0x00,0x00,0x88,
0xE7,0xBD,0xEE,0xF5,0xC8,0xF5,0x85,0xF0,0x00,0x00,
0x00,0x00,0x00,0x88,0x30,0x0D,0x06,0x09,0x2A,0x86,
0x48,0x86,0xF7,0x0D,0x01,0x01,0x05,0x05,0x00,0x30,
0x45,0x31,0x15,0x30,0x13,0x06,0x0A,0x09,0x92,0x26,
0x89,0x93,0xF2,0x2C,0x64,0x01,0x19,0x16,0x05,0x6C,
0x6F,0x63,0x61,0x6C,0x31,0x17,0x30,0x15,0x06,0x0A,
0x09,0x92,0x26,0x89,0x93,0xF2,0x2C,0x64,0x01,0x19,
0x16,0x07,0x74,0x65,0x73,0x74,0x69,0x6E,0x67,0x31,
0x13,0x30,0x11,0x06,0x03,0x55,0x04,0x03,0x13,0x0A,
0x54,0x65,0x73,0x74,0x69,0x6E,0x67,0x2D,0x43,0x41,
0x30,0x1E,0x17,0x0D,0x31,0x35,0x30,0x38,0x32,0x30,
0x30,0x36,0x33,0x37,0x33,0x34,0x5A,0x17,0x0D,0x31,
0x37,0x30,0x38,0x32,0x30,0x30,0x36,0x34,0x37,0x33,
0x34,0x5A,0x30,0x4F,0x31,0x15,0x30,0x13,0x06,0x0A,
0x09,0x92,0x26,0x89,0x93,0xF2,0x2C,0x64,0x01,0x19,
0x16,0x05,0x6C,0x6F,0x63,0x61,0x6C,0x31,0x17,0x30,
0x15,0x06,0x0A,0x09,0x92,0x26,0x89,0x93,0xF2,0x2C,
0x64,0x01,0x19,0x16,0x07,0x74,0x65,0x73,0x74,0x69,
0x6E,0x67,0x31,0x0D,0x30,0x0B,0x06,0x03,0x55,0x04,
0x0B,0x13,0x04,0x48,0x6F,0x6D,0x65,0x31,0x0E,0x30,
0x0C,0x06,0x03,0x55,0x04,0x03,0x13,0x05,0x4A,0x61,
0x73,0x6F,0x6E,0x30,0x82,0x01,0x22,0x30,0x0D,0x06,
0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x01,
0x05,0x00,0x03,0x82,0x01,0x0F,0x00,0x30,0x82,0x01,
0x0A,0x02,0x82,0x01,0x01,0x00,0xAA,0x6C,0x65,0xDD,
0x4E,0x12,0x62,0x5E,0xBB,0xB3,0x3C,0x46,0x04,0x2A,
0xF7,0xFE,0x9F,0x10,0xB4,0x73,0x38,0x57,0x11,0x97,
0x07,0x56,0x52,0x75,0x43,0x14,0x65,0x2C,0x6F,0xA2,
0xDD,0x14,0xE5,0x31,0x65,0x5C,0x38,0x79,0x94,0x8E,
0x2D,0x1E,0x3B,0x13,0xF0,0x8D,0x8F,0x83,0xD1,0xA6,
0x89,0x87,0xE7,0x33,0x8F,0xD2,0xFA,0x9D,0x28,0x3F,
0x66,0x24,0xDB,0xB9,0xBD,0x23,0x88,0xAA,0xCC,0x9D,
0xE0,0x88,0xE6,0x37,0xD8,0x0B,0x04,0x26,0x39,0x8C,
0xBD,0xAA,0x30,0x22,0xBF,0xB4,0xB3,0xAB,0x43,0x5D,
0xC1,0xB1,0x12,0x64,0xD7,0xF6,0x57,0xB4,0x9B,0x34,
0x66,0x28,0x71,0x06,0x0A,0x71,0xC6,0x95,0xF0,0x8E,
0x9F,0x5B,0x08,0xFE,0x3D,0x0A,0x24,0x5A,0x36,0xAD,
0xF9,0x3D,0x37,0x76,0x8C,0xA6,0x8B,0xD1,0xCD,0xB9,
0x13,0x57,0x1F,0x3A,0xB3,0x0A,0x3B,0xE7,0x1E,0xF0,
0xD1,0xFD,0xB2,0x0D,0x54,0xDE,0x9A,0x45,0xD2,0x2F,
0x63,0x32,0xE4,0x0B,0xD7,0xBE,0x86,0xF0,0xF7,0xAD,
0x3B,0xE8,0x04,0x73,0x32,0xDF,0x78,0xE4,0xCC,0xE1,
0xD4,0x91,0x34,0x34,0xFA,0x44,0x30,0x25,0x7B,0x13,
0x1C,0xC6,0x29,0x56,0x57,0xA2,0x89,0xDB,0x1C,0x60,
0xCE,0xF3,0xE4,0x8B,0xD9,0x28,0xFA,0xE1,0xF7,0xC4,
0xCE,0xF2,0xA9,0x29,0xCF,0xCC,0xFD,0x84,0x83,0xE5,
0xBB,0x43,0xB2,0xE0,0xC0,0x10,0x92,0xB3,0x75,0xEE,
0xBD,0x06,0x48,0xEF,0x5E,0x44,0x91,0x85,0xEF,0x0F,
0xEB,0x4C,0x24,0xB2,0xC0,0x68,0xBD,0x47,0xBC,0xE7,
0x8F,0x23,0xBC,0x08,0x77,0x36,0x44,0x47,0xAD,0x0A,
0x3D,0x67,0x02,0x03,0x01,0x00,0x01,0xA3,0x82,0x02,
0x91,0x30,0x82,0x02,0x8D,0x30,0x3E,0x06,0x09,0x2B,
0x06,0x01,0x04,0x01,0x82,0x37,0x15,0x07,0x04,0x31,
0x30,0x2F,0x06,0x27,0x2B,0x06,0x01,0x04,0x01,0x82,
0x37,0x15,0x08,0x87,0xDC,0xA1,0x40,0x86,0x93,0xE1,
0x24,0x85,0x99,0x9F,0x15,0x84,0xEB,0xF1,0x6B,0x84,
0x9C,0xD4,0x02,0x81,0x0E,0x85,0x90,0xA5,0x2C,0x83,
0x93,0xA7,0x6E,0x02,0x01,0x64,0x02,0x01,0x14,0x30,
0x1E,0x06,0x03,0x55,0x1D,0x25,0x04,0x17,0x30,0x15,
0x06,0x09,0x2B,0x06,0x01,0x04,0x01,0x82,0x37,0x50,
0x01,0x06,0x08,0x2B,0x06,0x01,0x05,0x05,0x07,0x03,
0x02,0x30,0x0E,0x06,0x03,0x55,0x1D,0x0F,0x01,0x01,
0xFF,0x04,0x04,0x03,0x02,0x05,0x20,0x30,0x28,0x06,
0x09,0x2B,0x06,0x01,0x04,0x01,0x82,0x37,0x15,0x0A,
0x04,0x1B,0x30,0x19,0x30,0x0B,0x06,0x09,0x2B,0x06,
0x01,0x04,0x01,0x82,0x37,0x50,0x01,0x30,0x0A,0x06,
0x08,0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x02,0x30,
0x1D,0x06,0x03,0x55,0x1D,0x0E,0x04,0x16,0x04,0x14,
0x07,0xA8,0x43,0xB0,0x8A,0xB6,0x27,0x5E,0x28,0xC4,
0x5C,0x9C,0x83,0x83,0x64,0x1D,0x98,0xF3,0x8A,0xAB,
0x30,0x1F,0x06,0x03,0x55,0x1D,0x23,0x04,0x18,0x30,
0x16,0x80,0x14,0x45,0x6F,0xDD,0xCC,0x30,0xF3,0xA5,
0xAD,0xB1,0xB8,0xD5,0x32,0x1F,0x1F,0xC2,0x1B,0x8C,
0xEB,0x0E,0xA4,0x30,0x81,0xC5,0x06,0x03,0x55,0x1D,
0x1F,0x04,0x81,0xBD,0x30,0x81,0xBA,0x30,0x81,0xB7,
0xA0,0x81,0xB4,0xA0,0x81,0xB1,0x86,0x81,0xAE,0x6C,
0x64,0x61,0x70,0x3A,0x2F,0x2F,0x2F,0x43,0x4E,0x3D,
0x54,0x65,0x73,0x74,0x69,0x6E,0x67,0x2D,0x43,0x41,
0x2C,0x43,0x4E,0x3D,0x44,0x43,0x2C,0x43,0x4E,0x3D,
0x43,0x44,0x50,0x2C,0x43,0x4E,0x3D,0x50,0x75,0x62,
0x6C,0x69,0x63,0x25,0x32,0x30,0x4B,0x65,0x79,0x25,
0x32,0x30,0x53,0x65,0x72,0x76,0x69,0x63,0x65,0x73,
0x2C,0x43,0x4E,0x3D,0x53,0x65,0x72,0x76,0x69,0x63,
0x65,0x73,0x2C,0x43,0x4E,0x3D,0x43,0x6F,0x6E,0x66,
0x69,0x67,0x75,0x72,0x61,0x74,0x69,0x6F,0x6E,0x2C,
0x44,0x43,0x3D,0x74,0x65,0x73,0x74,0x69,0x6E,0x67,
0x2C,0x44,0x43,0x3D,0x6C,0x6F,0x63,0x61,0x6C,0x3F,
0x63,0x65,0x72,0x74,0x69,0x66,0x69,0x63,0x61,0x74,
0x65,0x52,0x65,0x76,0x6F,0x63,0x61,0x74,0x69,0x6F,
0x6E,0x4C,0x69,0x73,0x74,0x3F,0x62,0x61,0x73,0x65,
0x3F,0x6F,0x62,0x6A,0x65,0x63,0x74,0x43,0x6C,0x61,
0x73,0x73,0x3D,0x63,0x52,0x4C,0x44,0x69,0x73,0x74,
0x72,0x69,0x62,0x75,0x74,0x69,0x6F,0x6E,0x50,0x6F,
0x69,0x6E,0x74,0x30,0x81,0xE8,0x06,0x08,0x2B,0x06,
0x01,0x05,0x05,0x07,0x01,0x01,0x04,0x81,0xDB,0x30,
0x81,0xD8,0x30,0x81,0xAB,0x06,0x08,0x2B,0x06,0x01,
0x05,0x05,0x07,0x30,0x02,0x86,0x81,0x9E,0x6C,0x64,
0x61,0x70,0x3A,0x2F,0x2F,0x2F,0x43,0x4E,0x3D,0x54,
0x65,0x73,0x74,0x69,0x6E,0x67,0x2D,0x43,0x41,0x2C,
0x43,0x4E,0x3D,0x41,0x49,0x41,0x2C,0x43,0x4E,0x3D,
0x50,0x75,0x62,0x6C,0x69,0x63,0x25,0x32,0x30,0x4B,
0x65,0x79,0x25,0x32,0x30,0x53,0x65,0x72,0x76,0x69,
0x63,0x65,0x73,0x2C,0x43,0x4E,0x3D,0x53,0x65,0x72,
0x76,0x69,0x63,0x65,0x73,0x2C,0x43,0x4E,0x3D,0x43,
0x6F,0x6E,0x66,0x69,0x67,0x75,0x72,0x61,0x74,0x69,
0x6F,0x6E,0x2C,0x44,0x43,0x3D,0x74,0x65,0x73,0x74,
0x69,0x6E,0x67,0x2C,0x44,0x43,0x3D,0x6C,0x6F,0x63,
0x61,0x6C,0x3F,0x63,0x41,0x43,0x65,0x72,0x74,0x69,
0x66,0x69,0x63,0x61,0x74,0x65,0x3F,0x62,0x61,0x73,
0x65,0x3F,0x6F,0x62,0x6A,0x65,0x63,0x74,0x43,0x6C,
0x61,0x73,0x73,0x3D,0x63,0x65,0x72,0x74,0x69,0x66,
0x69,0x63,0x61,0x74,0x69,0x6F,0x6E,0x41,0x75,0x74,
0x68,0x6F,0x72,0x69,0x74,0x79,0x30,0x28,0x06,0x08,
0x2B,0x06,0x01,0x05,0x05,0x07,0x30,0x01,0x86,0x1C,
0x68,0x74,0x74,0x70,0x3A,0x2F,0x2F,0x64,0x63,0x2E,
0x74,0x65,0x73,0x74,0x69,0x6E,0x67,0x2E,0x6C,0x6F,
0x63,0x61,0x6C,0x2F,0x6F,0x63,0x73,0x70,0x30,0x0D,
0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,
0x05,0x05,0x00,0x03,0x82,0x02,0x01,0x00,0x83,0xF9,
0x72,0x6A,0x54,0x51,0xC7,0x81,0x10,0x3E,0x82,0x38,
0x78,0x95,0x81,0xE0,0x8E,0x23,0xDF,0x89,0xB7,0x50,
0xD2,0x2E,0xC0,0xFF,0x7E,0x7A,0xDA,0x68,0xD2,0x5F,
0x8D,0x1A,0xA3,0x90,0x5B,0x1F,0x5A,0x3C,0x60,0xB4,
0x88,0x42,0xA9,0x6D,0xF0,0x35,0x5C,0xDD,0x8D,0x35,
0xE0,0x17,0x51,0x9E,0x52,0xD3,0xC3,0x58,0x5B,0x10,
0xD0,0x76,0x3E,0x9A,0x8A,0xA3,0xCE,0x1E,0xBF,0xCF,
0xA9,0x40,0x5D,0xC1,0x16,0x25,0x07,0x25,0x46,0xE7,
0x3D,0x0A,0x34,0x8F,0xD3,0x16,0x21,0x39,0x7D,0x7E,
0x54,0x64,0x52,0x45,0x54,0x0A,0x57,0xB0,0xCB,0xCD,
0x41,0x29,0x96,0xA6,0x5D,0x8C,0xD9,0x0F,0x45,0x3B,
0x40,0x06,0xB0,0x30,0x85,0x50,0x6C,0xE7,0xCE,0xDA,
0x0D,0xA2,0xA6,0x21,0x8D,0x1D,0x83,0xF0,0x3F,0xF8,
0xA7,0x2B,0x58,0x00,0xF7,0x99,0x21,0x24,0xEA,0x87,
0x5B,0xBB,0x6F,0xEB,0xB1,0x31,0x93,0x45,0xD6,0xFA,
0x0D,0x22,0xB3,0x8A,0x88,0xCC,0x4F,0x60,0x07,0x11,
0x16,0x14,0xDB,0x94,0x89,0x9D,0x74,0xE1,0x70,0xED,
0x45,0x18,0x2C,0x09,0xA3,0xB5,0x94,0x23,0xA6,0x66,
0x3E,0xD2,0xB0,0xA2,0xE3,0x23,0x32,0x90,0x96,0xAB,
0xB3,0xB5,0x22,0x27,0xB6,0x06,0xFF,0x6F,0x3D,0xA4,
0x46,0x67,0xA7,0xC9,0xD5,0x5C,0x43,0x88,0x66,0x37,
0xE8,0x4A,0xD3,0x9E,0x43,0x4F,0xA3,0x93,0x39,0x6F,
0x15,0x6E,0xCD,0x48,0x99,0xC1,0x54,0x7E,0xE3,0x12,
0xEC,0x89,0xCC,0x22,0xDE,0x3E,0x12,0x13,0xB5,0x32,
0x1A,0x3E,0xD2,0xA3,0x21,0x6A,0xC5,0xAD,0x81,0x8E,
0x2F,0x9E,0x61,0xBD,0x50,0xAE,0x23,0xE5,0xB7,0xF7,
0x24,0xD1,0x28,0x39,0x99,0xB0,0xCD,0x74,0x47,0xA1,
0xB5,0xD0,0x09,0x53,0xEA,0xD8,0xAB,0x23,0x37,0x7A,
0x3C,0xAC,0x0D,0x7C,0xD0,0x86,0x44,0xD0,0x2B,0x76,
0x04,0xC9,0x1C,0x29,0x08,0x9E,0x7E,0xCD,0x7E,0xEC,
0x0A,0x31,0x75,0x97,0x3B,0xD3,0x39,0x45,0xDA,0xCD,
0xDB,0xC3,0x6E,0x6E,0x51,0x3C,0xCE,0x02,0x00,0x16,
0xDE,0xFF,0xDD,0x45,0x34,0xD4,0x12,0xDF,0x9D,0x35,
0x6F,0xC2,0x06,0x53,0x18,0xF5,0x71,0x3D,0x50,0xF7,
0xE1,0xF3,0x08,0x4D,0xFC,0xC2,0xC4,0x53,0xD6,0xB6,
0xBE,0xD3,0xBC,0x8B,0xE3,0xF8,0xAC,0xE9,0xD0,0x54,
0xAD,0x5F,0x44,0x7C,0xE0,0x55,0xFD,0xAA,0x28,0xD1,
0x74,0xDB,0xAB,0x41,0xB5,0x7B,0x0C,0x04,0x0A,0x9F,
0xAA,0xBE,0x34,0xF0,0x27,0x41,0xA6,0xF7,0xAE,0xF9,
0x24,0x3F,0x27,0x87,0x64,0xBD,0x36,0x02,0xF7,0x69,
0x08,0x84,0x4B,0x30,0x95,0x4A,0xCF,0x17,0xE5,0x96,
0xB3,0x20,0x4B,0x60,0x3A,0xC2,0x22,0x6D,0xFF,0x35,
0x04,0x60,0x3A,0x51,0xF0,0xDB,0x0B,0x51,0x7B,0x44,
0x4C,0x55,0x40,0xE0,0x17,0x88,0x3D,0x5D,0xD8,0x6E,
0x2B,0x87,0xCB,0xE3,0xE9,0x4D,0x2B,0x8B,0x59,0x85,
0x38,0x04,0x39,0xCF,0x44,0x6B,0x73,0x85,0x21,0x01,
0x25,0x51,0xAB,0x69,0xAA,0x33,0x03,0x13,0x50,0x2C,
0xEC,0x69,0xE4,0xCC,0x51,0x3C,0xDF,0x44,0xAF,0xE5,
0x5A,0xEC,0x57,0x1A,0xFB,0x5F,0x4F,0x7E,0x0C,0xFD,
0xC4,0xA0,0xC3,0x9D,0xD0,0x60,0x83,0x79,0x8B,0x65,
0xAF,0x2A,0xD3,0x00,0x46,0x49,0x86,0x8E,0x55,0xD3



# Create an X.509 certificate object from the byte array.  Note the comma in the -ArgumentList argument
# to trick PowerShell into passing in the array as a single object instead of the array's contents.
$Cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$CertBytes)


# Now use the in-memory certificate object with Protect-CmsMessage before
# sending the data with Send-MailMessage, Invoke-WebRequest, etc.
$body = Protect-CmsMessage -To $Cert -Content "message data" 




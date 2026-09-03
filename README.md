# spec2attrib
Clinical programming teams frequently rely on Excel specifications to define dataset
attributes such as variable type, length, label, format, and key sequence. Translating
these specifications into consistent SAS code can be repetitive, error-prone, and
difficult to maintain across studies. This paper presents %spec2attrib, a reusable SAS
macro that imports domain-level metadata from an Excel specification, generates a
domain-specific ATTRIB block, and applies the resulting attributes directly to an input
dataset. The macro avoids shell-dataset workflows, reduces manual coding, and
improves consistency between metadata and delivered datasets.
The implementation uses DATA-step code generation with a temporary include file,
allowing attributes to be compiled before the SET statement and making the generated
code easy to inspect during debugging. The macro also removes inherited formats and
informats from the input dataset before applying specification-driven attributes,
helping prevent unintended metadata carryover. Additional features include parameter
validation, duplicate handling, optional spec subsetting, derivation of sort keys from
metadata, and optional debug comparison between input and output datasets.
%spec2attrib is intended as a lightweight, production-oriented utility for SDTM and
ADaM workflows. It occupies a practical middle ground between simple macro-variable
substitution methods and enterprise-scale metadata frameworks.

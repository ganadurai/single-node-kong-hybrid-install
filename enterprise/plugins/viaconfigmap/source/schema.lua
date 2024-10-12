return {
   name = "viaconfigmap",
   fields = {
     { config = {
         type = "record",
         fields = {
           { header_value = { type = "string", default = "default-value-configmap", }, },
         },
     }, },
   }
 }
 

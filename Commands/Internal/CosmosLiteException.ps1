class CosmosLiteException : Exception {
    [string] $Code
    [PSCustomObject] $Request

    CosmosLiteException($Code, $Message) : base($Message) {
        $this.Code = $code
        $this.Request = $null
    }
    CosmosLiteException($Code, $Message, $request) : base($Message) {
        $this.Code = $code
        $this.Request = $request
    }

    [string] ToString() {
        return "$($this.Code): $($this.Message)"
     }
}

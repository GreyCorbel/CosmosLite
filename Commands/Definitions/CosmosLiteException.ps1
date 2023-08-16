class CosmosLiteException : Exception {
    [string] $code

    CosmosLiteException($Code, $Message) : base($Message) {
        $this.Code = $code
    }

    [string] ToString() {
        return "$($this.Code): $($this.Message)"
     }
}

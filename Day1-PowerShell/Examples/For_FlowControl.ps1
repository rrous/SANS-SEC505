
For ( $i = 0 ; $i -le 20 ; $i++ ) {
	"Now at $i"
}

# $(...) is grouping expression, multiple commands can be run in each statement 
For ( $( $i=0; $j=0; $ps=@(get-process|select-object name)); 
      $( $ps.count -ge ($i + $j) ) ; 
      $( $i += 1 ; $j++ ) 
    ) 
{
	[string]$i + " " + [string]$j + " " + $ps[$i]
}
 
void main() {
    import std.stdio;
    import std.range;
    import multirange;
    
    auto X = 
        iota(100)
       .toMulti   // Convert range to a multi-range with 1 slot
       .multimap!(
            0, x =>  x, // Maps FROM slot 0, into slot 0
            0, x => -x) // Maps FROM slot 0, into slot 1
       .multifilter!(
            0, x => x >=  25 && x <=  50,  // Filter from slot 0, into slot 0
            1, x => x >= -50 && x <= -25)  // Filter from slot 1, into slot 1
       .arrays; // Collapse into a static array;
    
    writeln(X);
    
    
    toMulti(10.iota, 20.iota, 30.iota) // Can use multiple ranges to initialize multiple slots
       .multifilter!(
            0, x => x >  5,
            1, x => x > 15,
            2, x => x > 25)
       .multieach!(
            0, writeln,
            1, writeln,
            2, writeln); // Write them all to the screen
    
    int x = 0;
    
    auto Y =
        multigenerate!(
            () => x++,
            () => x++,
            () => x++,
            () => x++)
       .multitake(4, 4, 4, 4) // Take 4 from each slot
       .arrays;
    
    writeln(Y);
}
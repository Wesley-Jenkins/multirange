import multirange;

void main() {
    import std.stdio : writeln;
    import std.range : iota;
    
    int s;
    
    auto arrs = toMulti(iota(50), iota(100))
       .multimap!(
            0, x => x,
            0, x => -x,
            1, x => x,
            1, x => -x)
       .multifilter!(
            0, x => x >= 25,
            1, x => x <= 25,
            2, x => x >= 25,
            3, x => x <= 25)
       .multiuntil!(
            0, x => x >= 75,
            1, x => x <= -75,
            2, x => x >= 75,
            3, x => x <= -75)
       .arrays;
    
    writeln(arrs);
}
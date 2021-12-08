module multirange;
/*
    A multirange contains multiple ranges in slots.
    While this sounds simple, the interface is very complex.
    It is recommempty that you do not use the interface itself; use the provided functions instead.
    Just look at the horrific implementation of multifilter if you want to see why it's discouraged.
    The general interface is multiFront!(size_t index) and multiPopFront!(size_t index).
    Note that sometimes, you can't get the front of a multirange, and sometimes you can't even pop the front!
    A multirange might have more values, but you just can't read them or pop them currently. */

import std.range;

/* Returns a map of dependencies:
    SlotDepMap!(0, 0, 1, 2) => [0: [0, 1], 1: [2], 2: [3]] */
enum SlotDepMap(Slots...) = (){
    size_t[][size_t] depMap;
    
    foreach (i, slot; Slots) {
        depMap[slot] ~= i;
    }
    
    return depMap;
}();

enum SlotMap(M) = (){
    size_t[size_t] slotMap;
    
    foreach (i, slot; M.slots) {
        slotMap[slot] = i;
    }
    
    return slotMap;
}();

template SlotTypes(M) {
    import std.meta : AliasSeq;
    
    alias types = AliasSeq!();
    
    static foreach (slot; M.slots) {
        types = AliasSeq!(types, typeof(M.init.multiFront!slot()));
    }
    
    alias SlotTypes = types;
}

enum SlotState {
    SLOT_GOOD,     // Currently holds a value
    SLOT_WAITING,  // There are more values, but we can't read them at the moment.
    SLOT_EMPTY,    // The range is empty.
}

auto slotReturn(T)(T value) {
    return SlotReturn!T(value);
}

struct SlotReturn(T) {
    SlotState state = SlotState.SLOT_WAITING;
    
    static if (!is(T == void)) {
        T value;
        
        this(T value) {
            this.state = SlotState.SLOT_GOOD;
            this.value = value;
        }
    }
    
    this(SlotState state) {
        this.state = state;
    }
}

auto toMulti(size_t slots, R)(R r) if (isInputRange!R) {
    import std.meta : Repeat;
    
    return r.toMulti.multimap!(Repeat!(slots, 0, (x => x)));
}

/* Converts a range to a multirange */
auto toMulti(Rs...)(Rs rs) {
    static struct MultiWrapper {
        import std.array : staticArray;
        import std.range : iota;
        
        enum slots = staticArray!(Rs.length.iota);
        
        Rs baseRange;
        
        auto multiFront(size_t slot)() {
            if (!baseRange[slot].empty)
                return slotReturn(baseRange[slot].front);
            else
                return typeof(return)(SlotState.SLOT_EMPTY);
        }
        
        auto multiPopFront(size_t slot)() {
            if (baseRange[slot].empty)
                return SlotReturn!void(SlotState.SLOT_EMPTY);
            
            baseRange[slot].popFront;
            
            return SlotReturn!void(SlotState.SLOT_GOOD);
        }
    }
    
    return MultiWrapper(rs);
}

auto multijoin(Ms...)(Ms ms) {
    /* ... */
}

auto multichain(Ms...)(Ms ms) {
    alias M = Ms[0];
    
    static struct Multichain {
        enum slots = Ms[0].slots;
        
        Ms baseRange;
        size_t[slots.length] pos;
        
        auto multiFront(size_t slot)() {
            if (pos[slot] >= Ms.length)
                return typeof(ms[0].multiFront!slot())(SlotState.SLOT_EMPTY);
            
            
            auto ret = (){
                final switch (pos[slot]) {
                    static foreach (i; 0 .. baseRange.length) {
                        case i: return baseRange[i].multiFront!slot;
                    }
                }
            }();
            
            if (ret.state == SlotState.SLOT_EMPTY) {
                pos[slot] += 1;
                return multiFront!slot;
            }
            
            return ret;
        }
        
        auto multiPopFront(size_t slot)() {
            if (pos[slot] >= Ms.length)
                return SlotReturn!void(SlotState.SLOT_EMPTY);
            
            auto ret = (){
                final switch (pos[slot]) {
                    static foreach (i; 0 .. baseRange.length) {
                        case i: return baseRange[i].multiPopFront!slot;
                    }
                }
            }();
            
            if (ret.state == SlotState.SLOT_EMPTY) {
                pos[slot] += 1;
                return multiPopFront!slot;
            }
            
            return ret;
        }
    }
    
    return Multichain(ms);
}

/* Map a multi-range */
template multimap(Fs...) {
    import std.meta : Stride;
    
    static assert(Fs.length % 2 == 0);
    enum outputSlots = Fs.length / 2;
    
    alias inputSlots = Stride!(2, Fs);
    alias inputFuncs = Stride!(2, Fs[1 .. $]);
    alias depMap = SlotDepMap!(inputSlots);
    
    auto multimap(M)(M m) {
        import std.meta : Stride;
        
        enum slotMap = SlotMap!M;
        alias slotTypes = SlotTypes!M;
        
        static struct MultiMap {
            import std.array : staticArray;
            import std.range : iota;
            
            enum slots = staticArray!(outputSlots.iota);
            
            M baseRange;
            bool[inputSlots.length] popped;
            bool[inputSlots.length] empty;
            
            this (M baseRange) {
                this.baseRange = baseRange;
            }
            
            auto multiFront(size_t slot)() {
                enum baseSlot = inputSlots[slot];
                alias baseFunc = inputFuncs[slot];
                
                /* Swapped in order so we can use typeof(return) because I'm lazy */
                if (!popped[slot]) {
                    auto ret = baseRange.multiFront!baseSlot;
                    
                    if (ret.state == SlotState.SLOT_GOOD)
                        return slotReturn(baseFunc(ret.value));
                    
                    else
                        return typeof(return)(ret.state);
                        
                } else {
                    return typeof(return)(SlotState.SLOT_WAITING);
                }
            }
            
            auto multiPopFront(size_t slot)() {
                enum baseSlot = inputSlots[slot];
                
                if (empty[slot])
                    return SlotReturn!void(SlotState.SLOT_EMPTY);
                
                if (popped[slot])
                    return SlotReturn!void(SlotState.SLOT_WAITING);
                
                popped[slot] = true;
                bool allPopped = true;
                
                static foreach(i; depMap[baseSlot]) {
                    if (!popped[i])
                        allPopped = false;
                }
                
                if (allPopped) {
                    auto ret = baseRange.multiPopFront!baseSlot;
                    
                    if (ret.state == SlotState.SLOT_WAITING) {
                        popped[slot] = false;
                        return SlotReturn!void(SlotState.SLOT_WAITING);
                    }
                    
                    static foreach(i; depMap[baseSlot])
                        popped[i] = false;
                    
                    if (ret.state == SlotState.SLOT_EMPTY) {
                        static foreach(i; depMap[baseSlot])
                            empty[i] = true;
                    }
                    
                    return ret;
                }
                
                return SlotReturn!void(SlotState.SLOT_GOOD);
            }
        }
        
        return MultiMap(m);
    }
}

/* Filter a multi-range */
template multifilter(Fs...) {
    import std.meta : Stride;
    
    static assert(Fs.length % 2 == 0);
    enum outputSlots = Fs.length / 2;
    
    alias inputSlots = Stride!(2, Fs);
    alias inputFuncs = Stride!(2, Fs[1 .. $]);
    alias depMap = SlotDepMap!(inputSlots);
    
    auto multifilter(M)(M m) {
        alias slotTypes = SlotTypes!M;
        
        struct MultiFilter {
            import std.array : staticArray;
            import std.range : iota;
            
            enum slots = staticArray!(outputSlots.iota);
            
            M baseRange;
            slotTypes buffer;
            bool[M.slots.length] fronted;
            bool[inputSlots.length] discardedFront;
            
            auto multiFront(size_t slot)() {
                enum baseSlot = inputSlots[slot];
                
                if (buffer[baseSlot].state == SlotState.SLOT_EMPTY)
                    return typeof(buffer[baseSlot])(SlotState.SLOT_EMPTY);
                
                if (discardedFront[slot])
                    return typeof(buffer[baseSlot])(SlotState.SLOT_WAITING);
                
                if (fronted[baseSlot])
                    return buffer[baseSlot];
                
                buffer[baseSlot] = baseRange.multiFront!baseSlot;
                
                if (buffer[baseSlot].state != SlotState.SLOT_GOOD)
                    return buffer[baseSlot];
                
                fronted[baseSlot] = true;
                
                static foreach (i; depMap[baseSlot]) {
                    if (!inputFuncs[i](buffer[baseSlot].value))
                        discardedFront[i] = true;
                }
                
                bool allDiscarded = true;
                
                static foreach (i; depMap[baseSlot]) {
                    if (!discardedFront[i])
                        allDiscarded = false;
                }
                
                if (allDiscarded) {
                    auto ret = baseRange.multiPopFront!baseSlot;
                    
                    if (ret.state == SlotState.SLOT_EMPTY) {
                        buffer[baseSlot].state = SlotState.SLOT_EMPTY;
                        
                    } else if (ret.state == SlotState.SLOT_GOOD) {
                        static foreach(i; depMap[baseSlot])
                            discardedFront[i] = false;
                        
                        fronted[baseSlot] = false;
                        
                        return multiFront!slot;
                    }
                }
                
                if (discardedFront[slot])
                    return typeof(buffer[baseSlot])(SlotState.SLOT_WAITING);
                
                return buffer[baseSlot];
            }
            
            auto multiPopFront(size_t slot)() {
                enum baseSlot = inputSlots[slot];
                
                if (buffer[baseSlot].state == SlotState.SLOT_EMPTY)
                    return SlotReturn!void(SlotState.SLOT_EMPTY);
                
                auto wasDiscarded = discardedFront[slot];
                discardedFront[slot] = true;
                
                bool allDiscarded = true;
                
                static foreach (i; depMap[baseSlot]) {
                    if (!discardedFront[i])
                        allDiscarded = false;
                }
                
                if (allDiscarded) {
                    auto ret = baseRange.multiPopFront!baseSlot;
                    
                    if (ret.state == SlotState.SLOT_EMPTY) {
                        buffer[baseSlot].state = SlotState.SLOT_EMPTY;
                        
                        return ret;
                    
                    } else if (ret.state == SlotState.SLOT_WAITING) {
                        discardedFront[slot] = wasDiscarded;
                        buffer[baseSlot].state = SlotState.SLOT_WAITING;
                        
                        return ret;
                        
                    } else {
                        static foreach(i; depMap[baseSlot])
                            discardedFront[i] = false;
                        
                        fronted[baseSlot] = false;
                    }
                }
                
                if (wasDiscarded)
                    return typeof(return)(SlotState.SLOT_WAITING);
                else
                    return typeof(return)(SlotState.SLOT_GOOD);
            }
        }
        
        return MultiFilter(m);
    }
}

template multiuntil(Fs...) {
    import std.meta : Stride;
    
    static assert(Fs.length % 2 == 0);
    enum outputSlots = Fs.length / 2;
    
    alias inputSlots = Stride!(2, Fs);
    alias inputFuncs = Stride!(2, Fs[1 .. $]);
    alias depMap = SlotDepMap!(inputSlots);
    
    auto multiuntil(M)(M m) {
        static struct MultiUntil {
            import std.array : staticArray;
            import std.range : iota;
            
            enum slots = staticArray!(outputSlots.iota);
            
            M baseRange;
            bool[inputSlots.length] empty;
            bool[inputSlots.length] popped;
            
            auto multiFront(size_t slot)() {
                enum baseSlot = inputSlots[slot];
                
                if (empty[slot])
                    return typeof(baseRange.multiFront!baseSlot())(SlotState.SLOT_EMPTY);
                
                if (popped[slot])
                    return typeof(return)(SlotState.SLOT_WAITING);
                
                auto ret = baseRange.multiFront!baseSlot;
                
                if (ret.state != SlotState.SLOT_GOOD)
                    return ret;
                
                if (inputFuncs[slot](ret.value))
                    empty[slot] = true;
                
                return ret;
            }
            
            auto multiPopFront(size_t slot)() {
                enum baseSlot = inputSlots[slot];
                
                if (empty[slot])
                    return SlotReturn!void(SlotState.SLOT_EMPTY);
                
                if (popped[slot])
                    return SlotReturn!void(SlotState.SLOT_WAITING);
                
                popped[slot] = true;
                bool allPopped = true;
                
                static foreach(i; depMap[baseSlot]) {
                    if (!empty[i] && !popped[i])
                        allPopped = false;
                }
                
                if (allPopped) {
                    auto ret = baseRange.multiPopFront!baseSlot;
                    
                    if (ret.state == SlotState.SLOT_WAITING) {
                        popped[slot] = false;
                        return SlotReturn!void(SlotState.SLOT_WAITING);
                    }
                    
                    static foreach(i; depMap[baseSlot])
                        popped[i] = false;
                    
                    if (ret.state == SlotState.SLOT_EMPTY) {
                        static foreach(i; depMap[baseSlot])
                            empty[i] = true;
                    }
                    
                    return ret;
                }
                
                return SlotReturn!void(SlotState.SLOT_GOOD);
            }
        }
        
        return MultiUntil(m);
    }
}

/* Each a multi-range */
template multieach(Fs...) {
    import std.meta : Stride;
    
    static assert(Fs.length % 2 == 0);
    
    alias inputSlots = Stride!(2, Fs);
    alias inputFuncs = Stride!(2, Fs[1 .. $]);
    
    void multieach(M)(M m) {
        bool allEmpty = false;
        
        alias slotTypes = SlotTypes!M;
        
        while (!allEmpty) {
            allEmpty = true;
            
            bool[inputSlots.length] emptySlots;
            
            static foreach (i, slot; inputSlots) {
                if (!emptySlots[slot]) {
                    auto ret = m.multiFront!slot;
                    
                    if (ret.state == SlotState.SLOT_GOOD) {
                        inputFuncs[i](ret.value);
                    
                        auto popRet = m.multiPopFront!slot;
                        
                        if (popRet.state == SlotState.SLOT_EMPTY)
                            emptySlots[slot] = true;
                            
                        else
                            allEmpty = false;
                    } else if (ret.state == SlotState.SLOT_WAITING)
                        allEmpty = false;
                }
            }
        }
    }
}

auto arrays(M)(M m) {
    typeof(m.multiFront!0().value)[][M.slots.length] ret;
    
    enum mixinString = (){
        import std.conv : to;
        
        string ret;
        
        foreach (i, slot; M.slots) {
            ret ~= slot.to!string ~ ", " ~ "(x) { ret[" ~ i.to!string ~ "] ~= x; }, ";
        }
        
        return "m.multieach!(" ~ ret ~ ");";
    }();
    
    mixin(mixinString);
    
    return ret;
}
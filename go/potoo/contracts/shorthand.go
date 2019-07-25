package contracts

import (
	"github.com/DexterLB/potoo/go/potoo/bus"
	"github.com/DexterLB/potoo/go/potoo/types"
	"github.com/valyala/fastjson"
)

func Property(t types.Type, b bus.Bus, handler bus.RetHandler, children map[string]Contract, dflt *fastjson.Value, async bool) Contract {
	subcontract := Map{
		"set": Callable{
			Handler:  handler,
			Async:    async,
			Argument: t,
			Retval:   types.Void(),
		},
	}
	if children != nil {
		for key := range children {
			subcontract[key] = children[key]
		}
	}
	return Value{
		Bus:         b,
		Subcontract: subcontract,
		Default:     dflt,
		Type:        t,
	}
}
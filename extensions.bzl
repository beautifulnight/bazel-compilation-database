# Copyright 2026 Aqrose Technology, Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Bzlmod support for bazel-compilation-database.

The rules need two repositories that cannot be expressed as plain bazel_deps
because their content depends on the local machine and on the caller's
configuration:

  - com_grail_bazel_config_compdb: a generated config.bzl holding the CUDA
    symbols, the resolved CUDA path and the global filter flags.
  - com_grail_bazel_output_base_util: OUTPUT_BASE for the current machine.

In WORKSPACE mode both come from `bazel_compdb_deps()`; under Bzlmod this
module extension creates them instead.
"""

load("//:config.bzl", "config_compdb_repository")
load("//:tools.bzl", "bazel_output_base_util")

_DEFAULT_GLOBAL_FILTER_FLAGS = [
    "-isysroot __BAZEL_XCODE_SDKROOT__",
]

_config_tag = tag_class(
    attrs = {
        "cuda_enable": attr.bool(
            default = False,
            doc = "Enable CUDA compiler support.",
        ),
        "global_filter_flags": attr.string_list(
            default = _DEFAULT_GLOBAL_FILTER_FLAGS,
            doc = "Flags to remove from the generated compilation commands.",
        ),
        "rules_cuda": attr.label(
            doc = ("Any label inside the rules_cuda repository of your own module graph, " +
                   "e.g. '@rules_cuda//cuda:defs.bzl'. Required when cuda_enable is True. " +
                   "compdb reads the CUDA toolchain that your rules_cuda registers instead " +
                   "of fetching a second copy of it."),
        ),
    },
    doc = "Configures bazel-compilation-database. Only honoured on the root module.",
)

def _bazel_compdb_extension_impl(module_ctx):
    cuda_enable = False
    global_filter_flags = _DEFAULT_GLOBAL_FILTER_FLAGS
    rules_cuda_repo = "@rules_cuda"

    # Both repositories below are shared by the whole module graph, so letting
    # dependencies configure them would make the result depend on module
    # resolution order. Only the root module gets a say.
    configs = []
    for module in module_ctx.modules:
        if module.is_root:
            configs = module.tags.config

    if len(configs) > 1:
        fail("bazel_compdb.config may only be called once")

    for config in configs:
        cuda_enable = config.cuda_enable
        global_filter_flags = config.global_filter_flags
        if cuda_enable:
            if config.rules_cuda == None:
                fail("bazel_compdb.config(cuda_enable = True) also needs " +
                     "rules_cuda = \"@rules_cuda//cuda:defs.bzl\". Add " +
                     "bazel_dep(name = \"rules_cuda\", version = ...) to your MODULE.bazel.")

            # Refer to the root module's rules_cuda by canonical name: this
            # repository is not visible under any apparent name from
            # com_grail_bazel_compdb. label.repo_name is version independent,
            # unlike a hard-coded "@@rules_cuda+" (Bazel 7 writes "~" instead).
            rules_cuda_repo = "@@" + config.rules_cuda.repo_name

    config_compdb_repository(
        name = "com_grail_bazel_config_compdb",
        cuda_enable = cuda_enable,
        global_filter_flags = global_filter_flags,
        rules_cuda_repo = rules_cuda_repo,
    )

    bazel_output_base_util(
        name = "com_grail_bazel_output_base_util",
    )

bazel_compdb = module_extension(
    implementation = _bazel_compdb_extension_impl,
    tag_classes = {
        "config": _config_tag,
    },
)

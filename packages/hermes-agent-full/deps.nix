{
  lib,
  python3,
  fetchPypi,
}:
let
  pyPkgs = python3.pkgs;

  mkSetuptoolsPackage =
    {
      pname,
      version,
      dependencies ? [ ],
      pythonImportsCheck ? [ ],
      relaxDeps ? [ ],
      pypiName ? pname,
      buildSystem ? [ pyPkgs.setuptools ],
      hash,
      description,
      homepage,
      license,
    }:
    pyPkgs.buildPythonPackage {
      inherit
        pname
        version
        dependencies
        pythonImportsCheck
        ;
      pyproject = true;

      src = fetchPypi {
        pname = pypiName;
        inherit version hash;
      };

      build-system = buildSystem;
      pythonRelaxDeps = relaxDeps;

      meta = with lib; {
        inherit description homepage license;
        sourceProvenance = with sourceTypes; [ fromSource ];
        platforms = platforms.all;
      };
    };

  mkWheelPackage =
    {
      pname,
      version,
      dependencies ? [ ],
      pythonImportsCheck ? [ ],
      pypiName,
      hash,
      description,
      homepage,
      license,
    }:
    pyPkgs.buildPythonPackage {
      inherit
        pname
        version
        dependencies
        pythonImportsCheck
        ;
      format = "wheel";

      src = fetchPypi {
        pname = pypiName;
        inherit version hash;
        format = "wheel";
        dist = "py3";
        python = "py3";
        abi = "none";
        platform = "any";
      };

      meta = with lib; {
        inherit description homepage license;
        sourceProvenance = with sourceTypes; [ binaryBytecode ];
        platforms = platforms.all;
      };
    };
in
rec {
  darabonba-core = mkWheelPackage {
    pname = "darabonba-core";
    pypiName = "darabonba_core";
    version = "1.0.5";
    hash = "sha256-Zxq428Ttwqj4gBPacWRoObuJFPElnvwGk1MkPvUuonw=";
    dependencies = with pyPkgs; [
      aiohttp
      requests
      pyPkgs."alibabacloud-tea"
    ];
    pythonImportsCheck = [ "darabonba.core" ];
    description = "Darabonba core runtime for Alibaba Cloud SDKs";
    homepage = "https://pypi.org/project/darabonba-core/";
    license = lib.licenses.asl20;
  };

  daytona-api-client = mkSetuptoolsPackage {
    pname = "daytona-api-client";
    pypiName = "daytona_api_client";
    version = "0.167.0";
    hash = "sha256-Yd4qDPlPr3dVxrvh+PnTX9Dm6UzQNGX/dntS5Irjdvo=";
    dependencies = with pyPkgs; [
      urllib3
      python-dateutil
      pydantic
      typing-extensions
    ];
    pythonImportsCheck = [ "daytona_api_client" ];
    description = "Sync Python client for Daytona API";
    homepage = "https://pypi.org/project/daytona-api-client/";
    license = lib.licenses.asl20;
  };

  daytona-api-client-async = mkSetuptoolsPackage {
    pname = "daytona-api-client-async";
    pypiName = "daytona_api_client_async";
    version = "0.167.0";
    hash = "sha256-5j6z7dYRGydB1us1DtfJIQD9YUfEbeWkeW59/DAJhTw=";
    dependencies = with pyPkgs; [
      urllib3
      python-dateutil
      aiohttp
      pyPkgs."aiohttp-retry"
      pydantic
      typing-extensions
    ];
    pythonImportsCheck = [ "daytona_api_client_async" ];
    description = "Async Python client for Daytona API";
    homepage = "https://pypi.org/project/daytona-api-client-async/";
    license = lib.licenses.asl20;
  };

  daytona-toolbox-api-client = mkSetuptoolsPackage {
    pname = "daytona-toolbox-api-client";
    pypiName = "daytona_toolbox_api_client";
    version = "0.167.0";
    hash = "sha256-X/e0FBaEZyIewUv0+zi9qKRTezTb4A4SyO7j/67m+cM=";
    dependencies = with pyPkgs; [
      urllib3
      python-dateutil
      pydantic
      typing-extensions
    ];
    pythonImportsCheck = [ "daytona_toolbox_api_client" ];
    description = "Sync Python client for Daytona toolbox API";
    homepage = "https://pypi.org/project/daytona-toolbox-api-client/";
    license = lib.licenses.asl20;
  };

  daytona-toolbox-api-client-async = mkSetuptoolsPackage {
    pname = "daytona-toolbox-api-client-async";
    pypiName = "daytona_toolbox_api_client_async";
    version = "0.167.0";
    hash = "sha256-xPmT4lQ5azPSNM8ATZclKZLLIP439fZj1GQK9r73quw=";
    dependencies = with pyPkgs; [
      urllib3
      python-dateutil
      aiohttp
      pyPkgs."aiohttp-retry"
      pydantic
      typing-extensions
    ];
    pythonImportsCheck = [ "daytona_toolbox_api_client_async" ];
    description = "Async Python client for Daytona toolbox API";
    homepage = "https://pypi.org/project/daytona-toolbox-api-client-async/";
    license = lib.licenses.asl20;
  };

  daytona = mkSetuptoolsPackage {
    pname = "daytona";
    version = "0.167.0";
    hash = "sha256-t0Zz1e1NWtFgh4gn1J/RWh9Oeu3DKXZxwqBdr7a+Ux0=";
    dependencies =
      with pyPkgs;
      [
        python-dotenv
        pydantic
        deprecated
        httpx
        aiofiles
        toml
        obstore
        websockets
        pyPkgs."python-multipart"
        pyPkgs."opentelemetry-api"
        pyPkgs."opentelemetry-sdk"
        pyPkgs."opentelemetry-exporter-otlp-proto-http"
        pyPkgs."opentelemetry-instrumentation-aiohttp-client"
        urllib3
      ]
      ++ [
        daytona-api-client
        daytona-api-client-async
        daytona-toolbox-api-client
        daytona-toolbox-api-client-async
      ];
    buildSystem = [ pyPkgs.poetry-core ];
    relaxDeps = [
      "aiofiles"
      "obstore"
      "opentelemetry-instrumentation-aiohttp-client"
      "websockets"
    ];
    pythonImportsCheck = [ "daytona" ];
    description = "Python SDK for Daytona sandboxes";
    homepage = "https://github.com/daytonaio/daytona-python-sdk";
    license = lib.licenses.asl20;
  };

  honcho-ai = mkSetuptoolsPackage {
    pname = "honcho-ai";
    pypiName = "honcho_ai";
    version = "2.1.1";
    hash = "sha256-0nPYbOPnNhdVwISw3cRBYNScWcU4snjfYG5kN72JOmE=";
    dependencies = with pyPkgs; [
      httpx
      pydantic
      typing-extensions
    ];
    pythonImportsCheck = [ "honcho" ];
    description = "Honcho AI Python client";
    homepage = "https://github.com/plastic-labs/honcho";
    license = lib.licenses.asl20;
  };

  dingtalk-stream = mkWheelPackage {
    pname = "dingtalk-stream";
    pypiName = "dingtalk_stream";
    version = "0.24.3";
    hash = "sha256-IWBANlaYWWKHi/YM31rfQWGfIQZzSOBvB6fH7r9ZQ60=";
    dependencies = with pyPkgs; [
      aiohttp
      requests
      websockets
    ];
    pythonImportsCheck = [ "dingtalk_stream" ];
    description = "DingTalk stream mode SDK";
    homepage = "https://pypi.org/project/dingtalk-stream/";
    license = lib.licenses.mit;
  };

  alibabacloud-gateway-dingtalk = mkSetuptoolsPackage {
    pname = "alibabacloud-gateway-dingtalk";
    pypiName = "alibabacloud_gateway_dingtalk";
    version = "1.0.2";
    hash = "sha256-rOqLCx0R4DlJE/CwiZ3dGcC/zqtxYGBEm1f8wlDOswA=";
    dependencies = [
      pyPkgs."alibabacloud-gateway-spi"
      pyPkgs."alibabacloud-tea-util"
    ];
    pythonImportsCheck = [ "alibabacloud_gateway_dingtalk" ];
    description = "Alibaba Cloud DingTalk gateway bindings";
    homepage = "https://pypi.org/project/alibabacloud-gateway-dingtalk/";
    license = lib.licenses.asl20;
  };

  alibabacloud-tea-openapi = mkSetuptoolsPackage {
    pname = "alibabacloud-tea-openapi";
    pypiName = "alibabacloud_tea_openapi";
    version = "0.4.4";
    hash = "sha256-GwkXvAPNSUF9pklF6ScxcW1T4uuHB7I19U5Ft0cyIc4=";
    dependencies =
      with pyPkgs;
      [
        pyPkgs."alibabacloud-credentials"
        pyPkgs."alibabacloud-gateway-spi"
        pyPkgs."alibabacloud-tea-util"
        cryptography
      ]
      ++ [ darabonba-core ];
    pythonImportsCheck = [ "alibabacloud_tea_openapi" ];
    description = "Alibaba Cloud Tea OpenAPI runtime";
    homepage = "https://pypi.org/project/alibabacloud-tea-openapi/";
    license = lib.licenses.asl20;
  };

  alibabacloud-dingtalk = mkSetuptoolsPackage {
    pname = "alibabacloud-dingtalk";
    pypiName = "alibabacloud_dingtalk";
    version = "2.2.43";
    hash = "sha256-kblUscnAHIF06SbfqsZk9I5iYssxiC81z1deMZqafIc=";
    dependencies = [
      pyPkgs."alibabacloud-endpoint-util"
      pyPkgs."alibabacloud-gateway-spi"
      pyPkgs."alibabacloud-openapi-util"
      pyPkgs."alibabacloud-tea-util"
    ]
    ++ [
      alibabacloud-gateway-dingtalk
      alibabacloud-tea-openapi
    ];
    pythonImportsCheck = [ "alibabacloud_dingtalk" ];
    description = "Alibaba Cloud DingTalk Python SDK";
    homepage = "https://pypi.org/project/alibabacloud-dingtalk/";
    license = lib.licenses.asl20;
  };

  lark-oapi = mkWheelPackage {
    pname = "lark-oapi";
    pypiName = "lark_oapi";
    version = "1.5.3";
    hash = "sha256-/aazK7ONIba9qulJecYAuUx8Uh6YWtreY6VOSz4gzDY=";
    dependencies = with pyPkgs; [
      requests
      requests-toolbelt
      pycryptodome
      websockets
      httpx
    ];
    pythonImportsCheck = [ "lark_oapi" ];
    description = "Feishu/Lark OpenAPI SDK";
    homepage = "https://pypi.org/project/lark-oapi/";
    license = lib.licenses.asl20;
  };
}
